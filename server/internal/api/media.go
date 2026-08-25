package api

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"mime"
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
	ErrMediaInUse         = errors.New("media is attached to a post")
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

func (s hmacMediaStorage) VerifyUploaded(ctx context.Context, asset mediaAsset) error {
	if s.baseURL == "" || len(s.secret) == 0 {
		return ErrStorageUnavailable
	}
	if asset.Status == "deleted" {
		return ErrInvalidMedia
	}
	verificationURL, err := s.SignUpload(
		ctx,
		asset.ID,
		asset.ObjectKey,
		asset.MimeType,
		time.Now().UTC().Add(5*time.Minute),
	)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, verificationURL, nil)
	if err != nil {
		return ErrStorageUnavailable
	}
	client := &http.Client{Timeout: 30 * time.Second}
	response, err := client.Do(req)
	if err != nil {
		return ErrStorageUnavailable
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusNotFound {
		return ErrInvalidMedia
	}
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return ErrStorageUnavailable
	}
	if response.ContentLength < 0 || response.ContentLength != asset.Size {
		return ErrInvalidMedia
	}
	contentType, _, err := mime.ParseMediaType(response.Header.Get("Content-Type"))
	if err != nil || !strings.EqualFold(contentType, asset.MimeType) {
		return ErrInvalidMedia
	}
	if checksum := strings.TrimSpace(response.Header.Get("X-Checksum-Sha256")); checksum != "" && (len(checksum) != 64 || !isHex(checksum) || !strings.EqualFold(checksum, asset.SHA256)) {
		return ErrInvalidMedia
	}
	_ = response.Body.Close()

	getRequest, err := http.NewRequestWithContext(ctx, http.MethodGet, verificationURL, nil)
	if err != nil {
		return ErrStorageUnavailable
	}
	getResponse, err := client.Do(getRequest)
	if err != nil {
		return ErrStorageUnavailable
	}
	defer getResponse.Body.Close()
	if getResponse.StatusCode == http.StatusNotFound {
		return ErrInvalidMedia
	}
	if getResponse.StatusCode < http.StatusOK || getResponse.StatusCode >= http.StatusMultipleChoices {
		return ErrStorageUnavailable
	}

	hasher := sha256.New()
	prefix := &limitedPrefixWriter{remaining: 1 << 20}
	written, err := io.Copy(
		io.MultiWriter(hasher, prefix),
		io.LimitReader(getResponse.Body, asset.Size+1),
	)
	if err != nil {
		return ErrStorageUnavailable
	}
	if written != asset.Size || !strings.EqualFold(hex.EncodeToString(hasher.Sum(nil)), asset.SHA256) {
		return ErrInvalidMedia
	}
	if err := verifyMediaContent(prefix.Bytes(), asset); err != nil {
		return err
	}
	return nil
}

type limitedPrefixWriter struct {
	buffer    bytes.Buffer
	remaining int
}

func (w *limitedPrefixWriter) Write(value []byte) (int, error) {
	length := len(value)
	if w.remaining <= 0 {
		return length, nil
	}
	toWrite := value
	if len(toWrite) > w.remaining {
		toWrite = toWrite[:w.remaining]
	}
	_, _ = w.buffer.Write(toWrite)
	w.remaining -= len(toWrite)
	return length, nil
}

func (w *limitedPrefixWriter) Bytes() []byte { return w.buffer.Bytes() }

func verifyMediaContent(prefix []byte, asset mediaAsset) error {
	detected, _, err := mime.ParseMediaType(http.DetectContentType(prefix))
	if err != nil || !strings.EqualFold(detected, asset.MimeType) {
		return ErrInvalidMedia
	}
	if !strings.HasPrefix(asset.MimeType, "image/") {
		return nil
	}

	var width, height int
	if asset.MimeType == "image/webp" {
		width, height, err = webPDimensions(prefix)
	} else {
		var config image.Config
		config, _, err = image.DecodeConfig(bytes.NewReader(prefix))
		width, height = config.Width, config.Height
	}
	if err != nil || width <= 0 || height <= 0 {
		return ErrInvalidMedia
	}
	if (asset.Width > 0 && asset.Width != width) || (asset.Height > 0 && asset.Height != height) {
		return ErrInvalidMedia
	}
	return nil
}

func webPDimensions(value []byte) (int, int, error) {
	if len(value) < 30 || string(value[:4]) != "RIFF" || string(value[8:12]) != "WEBP" {
		return 0, 0, ErrInvalidMedia
	}
	switch string(value[12:16]) {
	case "VP8X":
		width := 1 + int(value[24]) + int(value[25])<<8 + int(value[26])<<16
		height := 1 + int(value[27]) + int(value[28])<<8 + int(value[29])<<16
		return width, height, nil
	case "VP8L":
		if len(value) < 25 || value[20] != 0x2f {
			return 0, 0, ErrInvalidMedia
		}
		width := 1 + int(value[21]) + int(value[22]&0x3f)<<8
		height := 1 + int(value[22]>>6) + int(value[23])<<2 + int(value[24]&0x0f)<<10
		return width, height, nil
	case "VP8 ":
		if len(value) < 30 || value[23] != 0x9d || value[24] != 0x01 || value[25] != 0x2a {
			return 0, 0, ErrInvalidMedia
		}
		width := int(value[26]) | int(value[27]&0x3f)<<8
		height := int(value[28]) | int(value[29]&0x3f)<<8
		return width, height, nil
	default:
		return 0, 0, ErrInvalidMedia
	}
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
	if len(input.SHA256) != 64 || !isHex(input.SHA256) {
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
