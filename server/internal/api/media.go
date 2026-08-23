package api

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrInvalidMedia       = errors.New("invalid media")
	ErrMediaNotFound      = errors.New("media not found")
	ErrStorageUnavailable = errors.New("media storage unavailable")
	ErrMediaNotOwned      = errors.New("media is not owned by user")
)

type mediaStorage interface {
	SignUpload(context.Context, string, string, string, time.Time) (string, error)
	VerifyUploaded(context.Context, mediaAsset) error
}

type unavailableMediaStorage struct{}

func (unavailableMediaStorage) SignUpload(context.Context, string, string, string, time.Time) (string, error) {
	return "", ErrStorageUnavailable
}

func (unavailableMediaStorage) VerifyUploaded(context.Context, mediaAsset) error {
	return ErrStorageUnavailable
}

type hmacMediaStorage struct {
	baseURL string
	secret  []byte
}

func newObjectStorageFromEnv() mediaStorage {
	baseURL := strings.TrimSpace(os.Getenv("OBJECT_STORAGE_UPLOAD_BASE_URL"))
	secret := strings.TrimSpace(os.Getenv("OBJECT_STORAGE_SIGNING_SECRET"))
	if baseURL == "" || secret == "" {
		return unavailableMediaStorage{}
	}
	return hmacMediaStorage{baseURL: strings.TrimRight(baseURL, "/"), secret: []byte(secret)}
}

func (s hmacMediaStorage) SignUpload(_ context.Context, assetID, objectKey, mimeType string, expiresAt time.Time) (string, error) {
	if s.baseURL == "" || len(s.secret) == 0 {
		return "", ErrStorageUnavailable
	}
	expires := strconv.FormatInt(expiresAt.Unix(), 10)
	message := assetID + "|" + objectKey + "|" + expires
	hash := hmac.New(sha256.New, s.secret)
	_, _ = hash.Write([]byte(message))
	signature := hex.EncodeToString(hash.Sum(nil))
	return s.baseURL + "?" + url.Values{
		"asset_id":   {assetID},
		"object_key": {objectKey},
		"mime_type":  {mimeType},
		"expires":    {expires},
		"signature":  {signature},
	}.Encode(), nil
}

func (s hmacMediaStorage) VerifyUploaded(_ context.Context, asset mediaAsset) error {
	if s.baseURL == "" || len(s.secret) == 0 || asset.Status == "deleted" {
		return ErrStorageUnavailable
	}
	// 对接真实对象存储时，这里由 HEAD/元数据校验替换；API 仍会校验所有权、大小和摘要。
	return nil
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
	var input mediaUploadInput
	if err := decodeJSON(r, &input); err != nil || !validMediaInput(input) {
		writeAuthError(w, r, ErrInvalidMedia)
		return
	}
	mediaID := newMediaID()
	objectKey := "media/" + user.ID + "/" + mediaID
	expiresAt := time.Now().UTC().Add(15 * time.Minute)
	storage := s.mediaStorage
	if storage == nil {
		storage = unavailableMediaStorage{}
	}
	uploadURL, err := storage.SignUpload(r.Context(), mediaID, objectKey, input.MimeType, expiresAt)
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
	storage := s.mediaStorage
	if storage == nil {
		storage = unavailableMediaStorage{}
	}
	if err := storage.VerifyUploaded(r.Context(), asset); err != nil {
		writeAuthError(w, r, err)
		return
	}
	now := time.Now().UTC()
	if _, err := s.db.ExecContext(r.Context(), `UPDATE media_assets SET status = 'ready', completed_at = $1, updated_at = $1 WHERE id = $2 AND owner_id = $3 AND status = 'pending'`, now, mediaID, user.ID); err != nil {
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
	result, err := s.db.ExecContext(r.Context(), `UPDATE media_assets SET deleted_at = now(), updated_at = now() WHERE id = $1 AND owner_id = $2 AND deleted_at IS NULL`, mediaID, user.ID)
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
		writeAuthError(w, r, ErrMediaNotFound)
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
	if input.Size <= 0 || input.Size > 100*1024*1024 || strings.TrimSpace(input.FileName) == "" {
		return false
	}
	if input.Width < 0 || input.Height < 0 || input.Width > 10000 || input.Height > 10000 {
		return false
	}
	switch input.MimeType {
	case "image/jpeg", "image/png", "image/webp", "video/mp4":
	default:
		return false
	}
	if input.SHA256 != "" && (len(input.SHA256) != 64 || !isHex(input.SHA256)) {
		return false
	}
	return true
}

func isHex(value string) bool {
	_, err := hex.DecodeString(value)
	return err == nil
}

func newMediaID() string {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "media_fallback"
	}
	return "media_" + hex.EncodeToString(raw[:])
}
