package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/config"
	"github.com/zhouwu97/luntan/server/internal/platform/database"
	"github.com/zhouwu97/luntan/server/internal/platform/logging"
)

type mediaItem struct {
	ID        string
	ObjectKey string
	MimeType  string
	Width     int
	Height    int
	Size      int64
	SHA256    string
}

func main() {
	batchSize := flag.Int("batch-size", 100, "Number of media records to process per batch")
	limit := flag.Int("limit", 0, "Maximum total records to backfill (0 = unlimited)")
	dryRun := flag.Bool("dry-run", false, "Preview records without writing outbox events")
	flag.Parse()

	cfg := config.Load()
	logger := logging.New(cfg.LogLevel)

	db, err := database.Open(cfg.DatabaseURL)
	if err != nil || db == nil {
		if err == nil {
			err = fmt.Errorf("database not configured")
		}
		logger.Error("backfill_db_failed", "error", err.Error())
		fmt.Fprintf(os.Stderr, "Error opening database: %v\n", err)
		os.Exit(1)
	}
	defer db.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	enqueued, err := RunBackfill(ctx, db, *batchSize, *limit, *dryRun)
	if err != nil {
		logger.Error("backfill_failed", "error", err.Error())
		fmt.Fprintf(os.Stderr, "Backfill error: %v\n", err)
		os.Exit(1)
	}

	if *dryRun {
		fmt.Printf("[Dry-Run] Scanned %d legacy ready media requiring variants backfill.\n", enqueued)
	} else {
		fmt.Printf("Successfully enqueued %d legacy ready media to outbox (media.process) for variant generation.\n", enqueued)
	}
}

func RunBackfill(ctx context.Context, db *sql.DB, batchSize, limit int, dryRun bool) (int, error) {
	if batchSize <= 0 {
		batchSize = 100
	}

	query := `
		SELECT ma.id, ma.object_key, ma.mime_type, ma.width, ma.height, ma.size, ma.sha256
		FROM media_assets ma
		WHERE ma.status = 'ready'
		  AND ma.deleted_at IS NULL
		  AND ma.mime_type LIKE 'image/%'
		  AND NOT (
		      EXISTS (SELECT 1 FROM media_variants mv
		              WHERE mv.media_id = ma.id AND mv.variant = 'original' AND mv.status = 'ready')
		      AND EXISTS (SELECT 1 FROM media_variants mv
		                  WHERE mv.media_id = ma.id AND mv.variant = 'detail' AND mv.status = 'ready')
		      AND EXISTS (SELECT 1 FROM media_variants mv
		                  WHERE mv.media_id = ma.id AND mv.variant = 'thumb' AND mv.status = 'ready')
		  )
		ORDER BY ma.created_at ASC
	`
	if limit > 0 {
		query += fmt.Sprintf(" LIMIT %d", limit)
	}

	rows, err := db.QueryContext(ctx, query)
	if err != nil {
		return 0, fmt.Errorf("query legacy media: %w", err)
	}
	defer rows.Close()

	items := make([]mediaItem, 0)
	for rows.Next() {
		var it mediaItem
		if err := rows.Scan(&it.ID, &it.ObjectKey, &it.MimeType, &it.Width, &it.Height, &it.Size, &it.SHA256); err != nil {
			return 0, fmt.Errorf("scan media item: %w", err)
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}
	rows.Close()

	if dryRun || len(items) == 0 {
		return len(items), nil
	}

	now := time.Now().UTC()
	enqueuedCount := 0

	for i := 0; i < len(items); i += batchSize {
		end := i + batchSize
		if end > len(items) {
			end = len(items)
		}
		batch := items[i:end]

		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return enqueuedCount, fmt.Errorf("begin backfill tx: %w", err)
		}

		for _, item := range batch {
			payloadBytes, err := json.Marshal(map[string]any{
				"media_id":   item.ID,
				"object_key": item.ObjectKey,
				"mime_type":  item.MimeType,
				"width":      item.Width,
				"height":     item.Height,
				"size_bytes": item.Size,
				"sha256":     item.SHA256,
			})
			if err != nil {
				_ = tx.Rollback()
				return enqueuedCount, fmt.Errorf("marshal payload: %w", err)
			}

			eventID := fmt.Sprintf("outbox_backfill_%s_%d", item.ID, now.UnixNano())
			_, err = tx.ExecContext(ctx, `
				INSERT INTO outbox_events (id, event_type, aggregate_type, aggregate_id, payload, status, attempts, available_at, created_at)
				VALUES ($1, 'media.process', 'media', $2, $3, 'pending', 0, $4, $4)
			`, eventID, item.ID, payloadBytes, now)
			if err != nil {
				_ = tx.Rollback()
				return enqueuedCount, fmt.Errorf("insert outbox event: %w", err)
			}
			enqueuedCount++
		}

		if err := tx.Commit(); err != nil {
			return enqueuedCount, fmt.Errorf("commit backfill tx: %w", err)
		}
	}

	return enqueuedCount, nil
}
