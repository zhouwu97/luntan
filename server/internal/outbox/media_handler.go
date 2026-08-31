package outbox

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/media"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

type StorageDeleter = storage.ObjectStorage

type MediaHandler struct {
	DB      *sql.DB
	Storage storage.ObjectStorage
}

type MediaProcessPayload struct {
	MediaID   string `json:"media_id"`
	ObjectKey string `json:"object_key"`
	MimeType  string `json:"mime_type"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	SizeBytes int64  `json:"size_bytes"`
	SHA256    string `json:"sha256"`
}

type MediaDeletePayload struct {
	MediaID   string   `json:"media_id"`
	ObjectKey string   `json:"object_key"`
	Variants  []string `json:"variants,omitempty"`
}

func (h MediaHandler) Handle(ctx context.Context, event Event) error {
	switch event.EventType {
	case "media.process":
		return h.handleProcess(ctx, event)
	case "media.delete":
		return h.handleDelete(ctx, event)
	default:
		return fmt.Errorf("media handler does not support event type: %s", event.EventType)
	}
}

func (h MediaHandler) handleProcess(ctx context.Context, event Event) error {
	var payload MediaProcessPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("decode media.process event: %w", err)
	}
	if payload.MediaID == "" || payload.ObjectKey == "" {
		return fmt.Errorf("media.process event missing media_id or object_key")
	}

	if h.DB == nil {
		return fmt.Errorf("media database unavailable: cannot process %s", payload.MediaID)
	}

	isVideo := strings.EqualFold(strings.TrimSpace(payload.MimeType), "video/mp4")
	readyVariants := "'source', 'original', 'detail', 'thumb'"
	readyTarget := 4
	if isVideo {
		// 视频当前只登记源对象，图片衍生图不能由视频处理链路伪造。
		readyVariants = "'source'"
		readyTarget = 1
	}

	// 幂等性检查：只有真实存在的核心变体才允许跳过处理。
	var readyCount int
	readyQuery := fmt.Sprintf(`
		SELECT COUNT(*) FROM media_variants
		WHERE media_id = $1 AND status = 'ready' AND variant IN (%s)
	`, readyVariants)
	if err := h.DB.QueryRowContext(ctx, readyQuery, payload.MediaID).Scan(&readyCount); err != nil {
		return fmt.Errorf("check media variants: %w", err)
	} else if readyCount == readyTarget {
		// 已完全就绪，保证幂等执行
		return nil
	}

	if h.Storage == nil {
		return fmt.Errorf("media storage unavailable: cannot process %s", payload.ObjectKey)
	}

	rc, _, _, err := h.Storage.Get(ctx, payload.ObjectKey)
	if err != nil {
		return fmt.Errorf("get source media: %w", err)
	}
	if rc == nil {
		return fmt.Errorf("get source media: empty reader")
	}

	var procRes *media.ProcessResult
	if isVideo {
		// 完整读取视频流，确保网络存储在标记 ready 前已经返回成功。
		if _, err := io.Copy(io.Discard, rc); err != nil {
			_ = rc.Close()
			return fmt.Errorf("read source video: %w", err)
		}
		if err := rc.Close(); err != nil {
			return fmt.Errorf("close source video: %w", err)
		}
	} else {
		if !strings.HasPrefix(strings.ToLower(strings.TrimSpace(payload.MimeType)), "image/") {
			_ = rc.Close()
			return fmt.Errorf("unsupported media mime type: %q", payload.MimeType)
		}
		procRes, err = media.ProcessImage(rc)
		closeErr := rc.Close()
		if err != nil {
			return fmt.Errorf("process image: %w", err)
		}
		if closeErr != nil {
			return fmt.Errorf("close source image: %w", closeErr)
		}
		if procRes == nil {
			return fmt.Errorf("process image: empty result")
		}

		origKey := payload.ObjectKey + "_original.jpg"
		detailKey := payload.ObjectKey + "_detail.jpg"
		thumbKey := payload.ObjectKey + "_thumb.jpg"
		// 只有三个真实对象全部上传成功后，下面的数据库事务才会写 ready。
		if err := h.Storage.Put(ctx, origKey, procRes.Original.MimeType, bytes.NewReader(procRes.Original.Data), procRes.Original.SizeBytes); err != nil {
			return fmt.Errorf("upload original variant: %w", err)
		}
		if err := h.Storage.Put(ctx, detailKey, procRes.Detail.MimeType, bytes.NewReader(procRes.Detail.Data), procRes.Detail.SizeBytes); err != nil {
			return fmt.Errorf("upload detail variant: %w", err)
		}
		if err := h.Storage.Put(ctx, thumbKey, procRes.Thumb.MimeType, bytes.NewReader(procRes.Thumb.Data), procRes.Thumb.SizeBytes); err != nil {
			return fmt.Errorf("upload thumb variant: %w", err)
		}
	}

	now := time.Now().UTC()

	tx, err := h.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// 1. source 变体（原始上传源文件）
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO media_variants (media_id, variant, object_key, mime_type, width, height, size_bytes, sha256, status, created_at, updated_at)
		VALUES ($1, 'source', $2, $3, $4, $5, $6, $7, 'ready', $8, $8)
		ON CONFLICT (media_id, variant) DO UPDATE SET
			object_key = EXCLUDED.object_key,
			width = EXCLUDED.width,
			height = EXCLUDED.height,
			size_bytes = EXCLUDED.size_bytes,
			sha256 = EXCLUDED.sha256,
			status = 'ready',
			updated_at = EXCLUDED.updated_at
	`, payload.MediaID, payload.ObjectKey, payload.MimeType, payload.Width, payload.Height, payload.SizeBytes, payload.SHA256, now); err != nil {
		return fmt.Errorf("save source variant: %w", err)
	}

	if isVideo {
		return tx.Commit()
	}

	// 2. original 变体（剥离元数据的高画质展示图）
	origKey := payload.ObjectKey + "_original.jpg"
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO media_variants (media_id, variant, object_key, mime_type, width, height, size_bytes, sha256, status, created_at, updated_at)
		VALUES ($1, 'original', $2, 'image/jpeg', $3, $4, $5, $6, 'ready', $7, $7)
		ON CONFLICT (media_id, variant) DO UPDATE SET
			object_key = EXCLUDED.object_key,
			width = EXCLUDED.width,
			height = EXCLUDED.height,
			size_bytes = EXCLUDED.size_bytes,
			sha256 = EXCLUDED.sha256,
			status = 'ready',
			updated_at = EXCLUDED.updated_at
	`, payload.MediaID, origKey, procRes.Original.Width, procRes.Original.Height, procRes.Original.SizeBytes, procRes.Original.SHA256, now); err != nil {
		return fmt.Errorf("save original variant: %w", err)
	}

	// 3. detail 变体（长边 <= 1440px）
	detailKey := payload.ObjectKey + "_detail.jpg"
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO media_variants (media_id, variant, object_key, mime_type, width, height, size_bytes, sha256, status, created_at, updated_at)
		VALUES ($1, 'detail', $2, 'image/jpeg', $3, $4, $5, $6, 'ready', $7, $7)
		ON CONFLICT (media_id, variant) DO UPDATE SET
			object_key = EXCLUDED.object_key,
			width = EXCLUDED.width,
			height = EXCLUDED.height,
			size_bytes = EXCLUDED.size_bytes,
			sha256 = EXCLUDED.sha256,
			status = 'ready',
			updated_at = EXCLUDED.updated_at
	`, payload.MediaID, detailKey, procRes.Detail.Width, procRes.Detail.Height, procRes.Detail.SizeBytes, procRes.Detail.SHA256, now); err != nil {
		return fmt.Errorf("save detail variant: %w", err)
	}

	// 4. thumb 变体（长边 <= 640px）
	thumbKey := payload.ObjectKey + "_thumb.jpg"
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO media_variants (media_id, variant, object_key, mime_type, width, height, size_bytes, sha256, status, created_at, updated_at)
		VALUES ($1, 'thumb', $2, 'image/jpeg', $3, $4, $5, $6, 'ready', $7, $7)
		ON CONFLICT (media_id, variant) DO UPDATE SET
			object_key = EXCLUDED.object_key,
			width = EXCLUDED.width,
			height = EXCLUDED.height,
			size_bytes = EXCLUDED.size_bytes,
			sha256 = EXCLUDED.sha256,
			status = 'ready',
			updated_at = EXCLUDED.updated_at
	`, payload.MediaID, thumbKey, procRes.Thumb.Width, procRes.Thumb.Height, procRes.Thumb.SizeBytes, procRes.Thumb.SHA256, now); err != nil {
		return fmt.Errorf("save thumb variant: %w", err)
	}

	return tx.Commit()
}

func (h MediaHandler) handleDelete(ctx context.Context, event Event) error {
	var payload MediaDeletePayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("decode media.delete event: %w", err)
	}
	if payload.MediaID == "" {
		return fmt.Errorf("media.delete event missing media_id")
	}

	keysToDelete := make([]string, 0)
	if payload.ObjectKey != "" {
		keysToDelete = append(keysToDelete, payload.ObjectKey)
	}

	if h.DB != nil {
		rows, err := h.DB.QueryContext(ctx, `SELECT object_key FROM media_variants WHERE media_id = $1`, payload.MediaID)
		if err != nil {
			return fmt.Errorf("list media variants for %s: %w", payload.MediaID, err)
		}
		for rows.Next() {
			var key string
			if err := rows.Scan(&key); err != nil {
				rows.Close()
				return fmt.Errorf("scan media variant key: %w", err)
			}
			if key != "" {
				keysToDelete = append(keysToDelete, key)
			}
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return fmt.Errorf("iterate media variants: %w", err)
		}
		rows.Close()
	}

	for _, k := range payload.Variants {
		if k != "" {
			keysToDelete = append(keysToDelete, k)
		}
	}

	// 物理删除对象存储中保存的源文件及所有生成衍生图。任何失败都必须返回
	// error 让 Worker 重试，静默吞掉会把删除事件标记为成功并永久泄漏对象。
	if len(keysToDelete) > 0 {
		if h.Storage == nil {
			return fmt.Errorf("media storage unavailable: cannot delete %s", payload.MediaID)
		}
		if err := h.Storage.DeleteMulti(ctx, keysToDelete); err != nil {
			return fmt.Errorf("delete media objects for %s: %w", payload.MediaID, err)
		}
	}

	if h.DB != nil {
		if _, err := h.DB.ExecContext(ctx, `DELETE FROM media_variants WHERE media_id = $1`, payload.MediaID); err != nil {
			return fmt.Errorf("delete media variant rows for %s: %w", payload.MediaID, err)
		}
	}
	return nil
}
