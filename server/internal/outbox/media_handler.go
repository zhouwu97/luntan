package outbox

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
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
		return nil
	}

	// 幂等性检查：如果该媒体的所有核心变体都已就绪且完整，则安全跳过或刷新
	var readyCount int
	if err := h.DB.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM media_variants
		WHERE media_id = $1 AND status = 'ready' AND variant IN ('source', 'original', 'detail', 'thumb')
	`, payload.MediaID).Scan(&readyCount); err == nil && readyCount == 4 {
		// 已完全就绪，保证幂等执行
		return nil
	}

	now := time.Now().UTC()

	// 变体默认值（以防无 storage 或非图片媒体时保持基础元数据）
	origKey := payload.ObjectKey + "_original.jpg"
	origW, origH := payload.Width, payload.Height
	origSize := payload.SizeBytes
	origSHA := payload.SHA256

	detailKey := payload.ObjectKey + "_detail.jpg"
	detailW, detailH := payload.Width, payload.Height
	if detailW > 1440 || detailH > 1440 {
		maxSide := detailW
		if detailH > maxSide {
			maxSide = detailH
		}
		scale := 1440.0 / float64(maxSide)
		detailW = int(float64(detailW) * scale)
		detailH = int(float64(detailH) * scale)
	}
	detailSize := payload.SizeBytes / 2
	detailSHA := payload.SHA256

	thumbKey := payload.ObjectKey + "_thumb.jpg"
	thumbW, thumbH := payload.Width, payload.Height
	if thumbW > 640 || thumbH > 640 {
		maxSide := thumbW
		if thumbH > maxSide {
			maxSide = thumbH
		}
		scale := 640.0 / float64(maxSide)
		thumbW = int(float64(thumbW) * scale)
		thumbH = int(float64(thumbH) * scale)
	}
	thumbSize := payload.SizeBytes / 4
	thumbSHA := payload.SHA256

	// 如果配置了对象存储，则真实下载源文件、解码、剥离 EXIF/GPS 并按比例生成各分辨率真实图片上传
	if h.Storage != nil {
		rc, _, _, err := h.Storage.Get(ctx, payload.ObjectKey)
		if err == nil && rc != nil {
			procRes, err := media.ProcessImage(rc)
			_ = rc.Close()
			if err == nil && procRes != nil {
				// 上传 original (去 EXIF 后的全分辨率图)
				if err := h.Storage.Put(ctx, origKey, procRes.Original.MimeType, bytes.NewReader(procRes.Original.Data), procRes.Original.SizeBytes); err != nil {
					return fmt.Errorf("upload original variant: %w", err)
				}
				origW, origH = procRes.Original.Width, procRes.Original.Height
				origSize = procRes.Original.SizeBytes
				origSHA = procRes.Original.SHA256

				// 上传 detail (长边 <= 1440px)
				if err := h.Storage.Put(ctx, detailKey, procRes.Detail.MimeType, bytes.NewReader(procRes.Detail.Data), procRes.Detail.SizeBytes); err != nil {
					return fmt.Errorf("upload detail variant: %w", err)
				}
				detailW, detailH = procRes.Detail.Width, procRes.Detail.Height
				detailSize = procRes.Detail.SizeBytes
				detailSHA = procRes.Detail.SHA256

				// 上传 thumb (长边 <= 640px)
				if err := h.Storage.Put(ctx, thumbKey, procRes.Thumb.MimeType, bytes.NewReader(procRes.Thumb.Data), procRes.Thumb.SizeBytes); err != nil {
					return fmt.Errorf("upload thumb variant: %w", err)
				}
				thumbW, thumbH = procRes.Thumb.Width, procRes.Thumb.Height
				thumbSize = procRes.Thumb.SizeBytes
				thumbSHA = procRes.Thumb.SHA256
			}
		}
	}

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

	// 2. original 变体（剥离元数据的高画质展示图）
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
	`, payload.MediaID, origKey, origW, origH, origSize, origSHA, now); err != nil {
		return fmt.Errorf("save original variant: %w", err)
	}

	// 3. detail 变体（长边 <= 1440px）
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
	`, payload.MediaID, detailKey, detailW, detailH, detailSize, detailSHA, now); err != nil {
		return fmt.Errorf("save detail variant: %w", err)
	}

	// 4. thumb 变体（长边 <= 640px）
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
	`, payload.MediaID, thumbKey, thumbW, thumbH, thumbSize, thumbSHA, now); err != nil {
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
		if err == nil {
			for rows.Next() {
				var key string
				if err := rows.Scan(&key); err == nil && key != "" {
					keysToDelete = append(keysToDelete, key)
				}
			}
			rows.Close()
		}
	}

	for _, k := range payload.Variants {
		if k != "" {
			keysToDelete = append(keysToDelete, k)
		}
	}

	// 物理删除对象存储中保存的源文件及所有生成衍生图
	if h.Storage != nil && len(keysToDelete) > 0 {
		_ = h.Storage.DeleteMulti(ctx, keysToDelete)
	}

	if h.DB != nil {
		_, _ = h.DB.ExecContext(ctx, `DELETE FROM media_variants WHERE media_id = $1`, payload.MediaID)
	}
	return nil
}
