package outbox

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type Event struct {
	ID            string
	EventType     string
	AggregateType string
	AggregateID   string
	Payload       json.RawMessage
	Attempts      int
}

type Handler interface {
	Handle(context.Context, Event) error
}

type NoopHandler struct{}

func (NoopHandler) Handle(context.Context, Event) error { return nil }

type RouterHandler struct {
	handlers map[string]Handler
	fallback Handler
}

func NewRouterHandler() *RouterHandler {
	return &RouterHandler{handlers: make(map[string]Handler)}
}

func (r *RouterHandler) Register(eventType string, handler Handler) {
	r.handlers[eventType] = handler
}

func (r *RouterHandler) SetFallback(handler Handler) {
	r.fallback = handler
}

func (r *RouterHandler) Handle(ctx context.Context, event Event) error {
	if h, ok := r.handlers[event.EventType]; ok {
		return h.Handle(ctx, event)
	}
	if r.fallback != nil {
		return r.fallback.Handle(ctx, event)
	}
	return fmt.Errorf("unhandled outbox event type: %s", event.EventType)
}

type Worker struct {
	DB          *sql.DB
	Handler     Handler
	BatchSize   int
	MaxAttempts int
	// Lease 是 processing 状态的租约时长：认领后超过该时长仍未写终态的任务
	// 视为 worker 崩溃遗留，允许被重新认领。<=0 时默认 5 分钟，必须大于最慢
	// 一类事件的真实处理耗时。
	Lease       time.Duration
	// Concurrency 是单个 worker 进程内并行处理事件的数量；<=0 时默认 4，
	// 避免图片解码等耗时处理阻塞后续通知类事件的消费。
	Concurrency int
	Now         func() time.Time
}

func (w Worker) RunOnce(ctx context.Context) (int, error) {
	if w.DB == nil {
		return 0, fmt.Errorf("outbox database is not configured")
	}
	batchSize := w.BatchSize
	if batchSize <= 0 {
		batchSize = 50
	}
	maxAttempts := w.MaxAttempts
	if maxAttempts <= 0 {
		maxAttempts = 8
	}
	lease := w.Lease
	if lease <= 0 {
		lease = 5 * time.Minute
	}
	now := time.Now
	if w.Now != nil {
		now = w.Now
	}
	tx, err := w.DB.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	// 崩溃恢复：processing 已提交但进程死亡的行永远不会被 pending/failed 分支
	// 选中，这里按租约超时把陈旧的 processing 一并纳入认领，由终态写入方
	// （成功/重试路径）保证锁外竞态下的最终一致。
	rows, err := tx.QueryContext(ctx, `
		SELECT id, event_type, aggregate_type, aggregate_id, payload, attempts
		FROM outbox_events
		WHERE (
			(status IN ('pending', 'failed') AND available_at <= $1 AND attempts < $2)
			OR (status = 'processing' AND locked_at < $3 AND attempts < $2)
		)
		ORDER BY created_at ASC, id ASC
		FOR UPDATE SKIP LOCKED LIMIT $4`,
		now().UTC(), maxAttempts, now().UTC().Add(-lease), batchSize)
	if err != nil {
		return 0, err
	}
	events := make([]Event, 0, batchSize)
	for rows.Next() {
		var event Event
		var payload []byte
		if err := rows.Scan(&event.ID, &event.EventType, &event.AggregateType, &event.AggregateID, &payload, &event.Attempts); err != nil {
			rows.Close()
			return 0, err
		}
		event.Payload = append(json.RawMessage(nil), payload...)
		events = append(events, event)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return 0, err
	}
	rows.Close()
	for _, event := range events {
		if _, err := tx.ExecContext(ctx, `UPDATE outbox_events SET status = 'processing', locked_at = $1, attempts = attempts + 1 WHERE id = $2`, now().UTC(), event.ID); err != nil {
			return 0, err
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}

	concurrency := w.Concurrency
	if concurrency <= 0 {
		concurrency = 4
	}
	if concurrency > len(events) {
		concurrency = len(events)
	}
	processed := int64(0)
	var firstErr error
	var mu sync.Mutex
	var wg sync.WaitGroup
	// 任一事件的状态更新失败就取消剩余处理，避免同一批次反复写库失败。
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	sem := make(chan struct{}, concurrency)
	for _, event := range events {
		wg.Add(1)
		sem <- struct{}{}
		go func(event Event) {
			defer wg.Done()
			defer func() { <-sem }()
			handler := w.Handler
			if handler == nil {
				handler = NoopHandler{}
			}
			handleErr := handler.Handle(ctx, event)
			if handleErr == nil {
				_, updateErr := w.DB.ExecContext(ctx, `UPDATE outbox_events SET status = 'succeeded', processed_at = $1, locked_at = NULL, last_error = '' WHERE id = $2`, now().UTC(), event.ID)
				if updateErr != nil {
					mu.Lock()
					if firstErr == nil {
						firstErr = updateErr
						cancel()
					}
					mu.Unlock()
					return
				}
				atomic.AddInt64(&processed, 1)
				return
			}
			backoff := time.Duration(1<<min(event.Attempts+1, 8)) * time.Second
			_, updateErr := w.DB.ExecContext(ctx, `UPDATE outbox_events SET status = CASE WHEN attempts >= $1 THEN 'failed' ELSE 'pending' END, available_at = $2, locked_at = NULL, last_error = $3 WHERE id = $4`, maxAttempts, now().UTC().Add(backoff), strings.TrimSpace(handleErr.Error()), event.ID)
			if updateErr != nil {
				mu.Lock()
				if firstErr == nil {
					firstErr = updateErr
					cancel()
				}
				mu.Unlock()
				return
			}
		}(event)
	}
	wg.Wait()
	return int(processed), firstErr
}

func min(left, right int) int {
	if left < right {
		return left
	}
	return right
}
