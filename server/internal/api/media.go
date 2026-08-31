package api

import (
	"bytes"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/media"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

var (
	ErrInvalidMedia       = storage.ErrInvalidMedia
	ErrMediaNotFound      = errors.New("media not found")
	ErrStorageUnavailable = storage.ErrStorageUnavailable
	ErrMediaNotOwned      = errors.New("media is not owned by user")
	ErrMediaInUse         = errors.New("media is attached to a post")
)

type mediaStorage = storage.ObjectStorage
type unavailableMediaStorage = storage.UnavailableMediaStorage

func newObjectStorageFromEnv() mediaStorage {
	return storage.NewObjectStorageFromEnv()
}

type mediaAsset struct {
	ID           string
	OwnerID      string
	ObjectKey    string
	OriginalName string
	MimeType     string
	Width        int
	Height       int
	Size         int64
	SHA256       string
	Status       string
	CreatedAt    time.Time
	UpdatedAt    time.Time
	CompletedAt  sql.NullTime
}

type mediaUploadInput struct {
	FileName string `json:"file_name"`
	MimeType string `json:"mime_type"`
	Width    int    `json:"width"`
	Height   int    `json:"height"`
	Size     int64  `json:"size"`
	SHA256   string `json:"sha256"`
}

type mediaCompleteInput struct {
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
}

type signedMediaUploadHandler interface {
	ServeSignedUpload(http.ResponseWriter, *http.Request)
}

func (s *Server) receiveSignedMediaUpload(w http.ResponseWriter, r *http.Request) {
	handler, ok := s.mediaStorage.(signedMediaUploadHandler)
	if !ok {
		writeAuthError(w, r, ErrStorageUnavailable)
		return
	}
	handler.ServeSignedUpload(w, r)
}

func (s *Server) createMediaUploadToken(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.requireCapability(w, r, user, capUploadMedia) {
		return
	}
	var input mediaUploadInput
	if err := decodeJSON(r, &input); err != nil || !validMediaInput(input) {
		writeAuthError(w, r, ErrInvalidMedia)
		return
	}
	mediaID, err := newMediaID()
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	objectKey := "media/" + user.ID + "/" + mediaID
	expiresAt := time.Now().UTC().Add(15 * time.Minute)
	storageBackend := s.mediaStorage
	if storageBackend == nil {
		storageBackend = unavailableMediaStorage{}
	}
	uploadURL, err := storageBackend.SignUpload(r.Context(), mediaID, objectKey, input.MimeType, expiresAt)
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	now := time.Now().UTC()
	if _, err := s.db.ExecContext(r.Context(), `INSERT INTO media_assets (id, owner_id, object_key, original_name, mime_type, width, height, size, sha256, status, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'pending', $10, $10)`, mediaID, user.ID, objectKey, filepath.Base(input.FileName), input.MimeType, input.Width, input.Height, input.Size, strings.ToLower(input.SHA256), now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, map[string]any{
		"media_id":      mediaID,
		"object_key":    objectKey,
		"upload_url":    uploadURL,
		"upload_method": "PUT",
		"expires_at":    expiresAt,
		"status":        "pending",
	})
}

func (s *Server) completeMedia(w http.ResponseWriter, r *http.Request, mediaID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if strings.TrimSpace(mediaID) == "" {
		writeAuthError(w, r, ErrMediaNotFound)
		return
	}
	var input mediaCompleteInput
	if r.Body != nil && r.ContentLength != 0 {
		if err := decodeJSON(r, &input); err != nil {
			writeAuthError(w, r, ErrInvalidMedia)
			return
		}
	}
	var asset mediaAsset
	err := s.db.QueryRowContext(r.Context(), `SELECT id, owner_id, object_key, original_name, mime_type, width, height, size, sha256, status, created_at, updated_at, completed_at FROM media_assets WHERE id = $1 AND deleted_at IS NULL`, mediaID).Scan(&asset.ID, &asset.OwnerID, &asset.ObjectKey, &asset.OriginalName, &asset.MimeType, &asset.Width, &asset.Height, &asset.Size, &asset.SHA256, &asset.Status, &asset.CreatedAt, &asset.UpdatedAt, &asset.CompletedAt)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrMediaNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if asset.OwnerID != user.ID {
		writeAuthError(w, r, ErrMediaNotOwned)
		return
	}
	if asset.Status == "ready" {
		httpserver.WriteJSON(w, http.StatusOK, mediaResponse(asset))
		return
	}
	if input.Size != 0 && input.Size != asset.Size || input.SHA256 != "" && !strings.EqualFold(input.SHA256, asset.SHA256) {
		writeAuthError(w, r, ErrInvalidMedia)
		return
	}
	storageBackend := s.mediaStorage
	if storageBackend == nil {
		storageBackend = unavailableMediaStorage{}
	}
	storageAsset := &storage.MediaAsset{
		ID:        asset.ID,
		ObjectKey: asset.ObjectKey,
		MimeType:  asset.MimeType,
		Width:     asset.Width,
		Height:    asset.Height,
		Size:      asset.Size,
		SHA256:    asset.SHA256,
		Status:    asset.Status,
	}
	if err := storageBackend.VerifyUploaded(r.Context(), storageAsset); err != nil {
		writeAuthError(w, r, err)
		return
	}
	asset.Width = storageAsset.Width
	asset.Height = storageAsset.Height

	now := time.Now().UTC()
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(r.Context(), `UPDATE media_assets SET status = 'ready', width = $1, height = $2, completed_at = $3, updated_at = $3 WHERE id = $4 AND owner_id = $5 AND status = 'pending'`, asset.Width, asset.Height, now, mediaID, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := enqueueOutboxTx(tx, "media.process", "media", mediaID, map[string]any{
		"media_id":   mediaID,
		"object_key": asset.ObjectKey,
		"mime_type":  asset.MimeType,
		"width":      asset.Width,
		"height":     asset.Height,
		"size_bytes": asset.Size,
		"sha256":     asset.SHA256,
	}, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	asset.Status, asset.UpdatedAt = "ready", now
	asset.CompletedAt = sql.NullTime{Time: now, Valid: true}
	httpserver.WriteJSON(w, http.StatusOK, mediaResponse(asset))
}

// mediaInUseExpr 枚举所有会把 deleted 媒体从展示中过滤掉的业务引用。
// 新增引用媒体的业务表时必须同步补到这里，否则媒体可被绕过业务直接删除。
const mediaInUseExpr = `EXISTS (SELECT 1 FROM post_media pm WHERE pm.media_id = ma.id)
		OR EXISTS (SELECT 1 FROM comment_media cm WHERE cm.media_id = ma.id)
		OR EXISTS (SELECT 1 FROM moderation_appeal_media mam WHERE mam.media_id = ma.id)
		OR EXISTS (SELECT 1 FROM ranking_toy_submissions rts WHERE rts.cover_media_id = ma.id)
		OR EXISTS (SELECT 1 FROM ranking_toys rt WHERE rt.cover_media_id = ma.id OR rt.hero_media_id = ma.id)
		OR EXISTS (SELECT 1 FROM ranking_toy_comment_media rtcm WHERE rtcm.media_id = ma.id)`

// deleteMedia 由作者清理尚未关联帖子的已上传媒体（放弃发布或单图删除），
// 防止 pending/ready 孤儿媒体长期堆积。
func (s *Server) deleteMedia(w http.ResponseWriter, r *http.Request, mediaID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if strings.TrimSpace(mediaID) == "" {
		writeAuthError(w, r, ErrMediaNotFound)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var ownerID string
	var inUse bool
	err = tx.QueryRowContext(r.Context(), `
		SELECT ma.owner_id, (
			`+mediaInUseExpr+`)
		FROM media_assets ma
		WHERE ma.id = $1 AND ma.deleted_at IS NULL
		FOR UPDATE OF ma`, mediaID).Scan(&ownerID, &inUse)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrMediaNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if ownerID != user.ID {
		writeAuthError(w, r, ErrMediaNotOwned)
		return
	}
	if inUse {
		writeAuthError(w, r, ErrMediaInUse)
		return
	}
	result, err := tx.ExecContext(r.Context(), `
		UPDATE media_assets ma
		SET deleted_at = now(), updated_at = now(), status = 'deleted'
		WHERE ma.id = $1 AND ma.owner_id = $2 AND ma.deleted_at IS NULL
		  AND NOT (
		  `+mediaInUseExpr+`)`, mediaID, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	affected, err := result.RowsAffected()
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if affected == 0 {
		writeAuthError(w, r, ErrMediaInUse)
		return
	}
	if err := enqueueOutboxTx(tx, "media.delete", "media", mediaID, map[string]any{
		"media_id": mediaID,
	}, time.Now().UTC()); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func mediaResponse(asset mediaAsset) map[string]any {
	return map[string]any{"id": asset.ID, "object_key": asset.ObjectKey, "mime_type": asset.MimeType, "width": asset.Width, "height": asset.Height, "size": asset.Size, "sha256": asset.SHA256, "status": asset.Status, "created_at": asset.CreatedAt, "updated_at": asset.UpdatedAt, "completed_at": nullableTime(asset.CompletedAt)}
}

func nullableTime(value sql.NullTime) any {
	if !value.Valid {
		return nil
	}
	return value.Time
}

func validMediaInput(input mediaUploadInput) bool {
	if input.Size <= 0 || strings.TrimSpace(input.FileName) == "" {
		return false
	}
	switch input.MimeType {
	case "image/jpeg", "image/png", "image/webp":
		if input.Size > 15*1024*1024 {
			return false
		}
	case "video/mp4":
		if input.Size > 100*1024*1024 {
			return false
		}
	default:
		return false
	}
	if input.Width < 0 || input.Height < 0 || input.Width > 10000 || input.Height > 10000 {
		return false
	}
	if input.Width > 0 && input.Height > 0 && int64(input.Width)*int64(input.Height) > 40_000_000 {
		return false
	}
	if len(input.SHA256) != 64 || !isHex(input.SHA256) {
		return false
	}
	return true
}

func isHex(value string) bool {
	_, err := hex.DecodeString(value)
	return err == nil
}

func newMediaID() (string, error) {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", errors.New("generate media id failed")
	}
	return "media_" + hex.EncodeToString(raw[:]), nil
}

// serveMediaFile 处理 GET/HEAD /api/v1/media-file/{objectKey} 的媒体下载兜底。
// 未配置 OBJECT_STORAGE_PUBLIC_BASE_URL 时，publicMediaURL 返回该路由的根
// 相对地址。免鉴权与公开 Feed 对齐；路径安全由存储层 objectPath 校验。
// 媒体对象内容不可变（写入时经 SHA256 校验），响应下发一年期 immutable
// 缓存头供浏览器/CDN 长缓存；本地存储返回 *os.File 时由 http.ServeContent
// 额外提供 Range 与条件请求支持。
func (s *Server) serveMediaFile(w http.ResponseWriter, r *http.Request, objectKey string) {
	backend := s.mediaStorage
	if backend == nil {
		writeAuthError(w, r, ErrStorageUnavailable)
		return
	}
	rc, size, contentType, err := backend.Get(r.Context(), objectKey)
	if err != nil {
		switch {
		case errors.Is(err, storage.ErrObjectNotFound):
			writeAuthError(w, r, ErrMediaNotFound)
		case errors.Is(err, storage.ErrInvalidMedia):
			writeAuthError(w, r, ErrInvalidMedia)
		default:
			writeAuthError(w, r, ErrStorageUnavailable)
		}
		return
	}
	defer rc.Close()
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	if contentType != "" {
		w.Header().Set("Content-Type", contentType)
	}
	if rs, ok := rc.(io.ReadSeeker); ok {
		http.ServeContent(w, r, "", time.Time{}, rs)
		return
	}
	w.Header().Set("Content-Length", strconv.FormatInt(size, 10))
	if r.Method == http.MethodHead {
		return
	}
	_, _ = io.Copy(w, rc)
}

type moderateMediaInput struct {
	ModerationStatus string             `json:"moderation_status"` // "censored" or "normal"
	MaskRegions      []media.MaskRegion `json:"mask_regions"`
	Reason           string             `json:"reason,omitempty"`
}

func (s *Server) moderateMedia(w http.ResponseWriter, r *http.Request, mediaID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasGlobalPermission(r, user.ID, "moderation.action") && !capabilitiesForUser(user)[capModerate] {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}

	var input moderateMediaInput
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BODY", Message: "请求体格式错误"})
		return
	}
	if input.ModerationStatus == "" {
		input.ModerationStatus = "censored"
	}
	if input.ModerationStatus != "censored" && input.ModerationStatus != "normal" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_STATUS", Message: "审核状态只能为 censored 或 normal"})
		return
	}

	var objectKey, mimeType string
	var status string
	err := s.db.QueryRowContext(r.Context(), `SELECT object_key, mime_type, status FROM media_assets WHERE id = $1 AND deleted_at IS NULL`, mediaID).Scan(&objectKey, &mimeType, &status)
	if errors.Is(err, sql.ErrNoRows) {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "MEDIA_NOT_FOUND", Message: "媒体不存在或已删除"})
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	now := time.Now().UTC()
	regionsJSON, _ := json.Marshal(input.MaskRegions)

	if input.ModerationStatus == "censored" && len(input.MaskRegions) > 0 {
		// 生成 censored 衍生图变体
		if s.mediaStorage != nil {
			rc, _, _, err := s.mediaStorage.Get(r.Context(), objectKey)
			if err == nil && rc != nil {
				data, readErr := io.ReadAll(rc)
				_ = rc.Close()
				if readErr == nil && len(data) > 0 {
					procRes, procErr := media.ProcessCensoredImage(bytes.NewReader(data), input.MaskRegions)
					if procErr == nil && procRes != nil {
						origKey := objectKey + "_censored_original.jpg"
						detailKey := objectKey + "_censored_detail.jpg"
						thumbKey := objectKey + "_censored_thumb.jpg"
						_ = s.mediaStorage.Put(r.Context(), origKey, procRes.Original.MimeType, bytes.NewReader(procRes.Original.Data), procRes.Original.SizeBytes)
						_ = s.mediaStorage.Put(r.Context(), detailKey, procRes.Detail.MimeType, bytes.NewReader(procRes.Detail.Data), procRes.Detail.SizeBytes)
						_ = s.mediaStorage.Put(r.Context(), thumbKey, procRes.Thumb.MimeType, bytes.NewReader(procRes.Thumb.Data), procRes.Thumb.SizeBytes)

						// 写入/更新 media_variants
						for _, v := range []struct {
							variant string
							key     string
							p       media.ProcessedVariant
						}{
							{"censored_original", origKey, procRes.Original},
							{"censored_detail", detailKey, procRes.Detail},
							{"censored_thumb", thumbKey, procRes.Thumb},
						} {
							_, _ = s.db.ExecContext(r.Context(), `
								INSERT INTO media_variants (media_id, variant, object_key, mime_type, width, height, size_bytes, sha256, status, created_at, updated_at)
								VALUES ($1, $2, $3, 'image/jpeg', $4, $5, $6, $7, 'ready', $8, $8)
								ON CONFLICT (media_id, variant) DO UPDATE SET
									object_key = EXCLUDED.object_key,
									width = EXCLUDED.width,
									height = EXCLUDED.height,
									size_bytes = EXCLUDED.size_bytes,
									sha256 = EXCLUDED.sha256,
									status = 'ready',
									updated_at = EXCLUDED.updated_at`,
								mediaID, v.variant, v.key, v.p.Width, v.p.Height, v.p.SizeBytes, v.p.SHA256, now)
						}
					}
				}
			}
		}
		_, err = s.db.ExecContext(r.Context(), `
			UPDATE media_assets
			SET moderation_status = 'censored',
			    mask_regions = $1::jsonb,
			    moderated_by = $2,
			    moderated_at = $3,
			    moderation_reason = $4,
			    updated_at = $3
			WHERE id = $5`, string(regionsJSON), user.ID, now, input.Reason, mediaID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	} else {
		// 恢复正常
		_, err = s.db.ExecContext(r.Context(), `
			UPDATE media_assets
			SET moderation_status = 'normal',
			    mask_regions = '[]'::jsonb,
			    moderated_by = $1,
			    moderated_at = $2,
			    moderation_reason = $3,
			    updated_at = $2
			WHERE id = $4`, user.ID, now, input.Reason, mediaID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	}

	_ = appendAdminLog(r.Context(), s.db, user.ID, "media.moderation", "media", mediaID, "", requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{
		"status":  input.ModerationStatus,
		"regions": input.MaskRegions,
		"reason":  input.Reason,
	}, now)

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"success":           true,
		"media_id":          mediaID,
		"moderation_status": input.ModerationStatus,
		"mask_regions":      input.MaskRegions,
	})
}
