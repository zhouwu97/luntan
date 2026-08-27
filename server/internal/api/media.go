package api

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"net/http"
	"path/filepath"
	"strings"
	"time"

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
		SELECT ma.owner_id, EXISTS (SELECT 1 FROM post_media pm WHERE pm.media_id = ma.id)
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
		  AND NOT EXISTS (SELECT 1 FROM post_media pm WHERE pm.media_id = ma.id)
		  AND NOT EXISTS (SELECT 1 FROM moderation_appeal_media mam WHERE mam.media_id = ma.id)`, mediaID, user.ID)
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
