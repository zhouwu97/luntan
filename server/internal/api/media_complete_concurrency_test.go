package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"image"
	"image/jpeg"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

// TestCompleteMediaDoesNotEnqueueAfterConcurrentWinner 锁定 complete 的关键
// 竞态：另一个请求已经把 pending 媒体迁移为 ready 时，当前请求的条件更新
// 必须识别为非 winner，并且不能再次写入 media.process outbox。
func TestCompleteMediaDoesNotEnqueueAfterConcurrentWinner(t *testing.T) {
	var raw bytes.Buffer
	if err := jpeg.Encode(&raw, image.NewRGBA(image.Rect(0, 0, 2, 2)), nil); err != nil {
		t.Fatal(err)
	}
	rawBytes := raw.Bytes()
	digest := sha256.Sum256(rawBytes)
	digestHex := hex.EncodeToString(digest[:])
	objectKey := "media/user-1/media-race"
	store := storage.NewMemoryStorage()
	if err := store.Put(context.Background(), objectKey, "image/jpeg", bytes.NewReader(rawBytes), int64(len(rawBytes))); err != nil {
		t.Fatal(err)
	}

	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	createdAt := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	mock.ExpectQuery(`SELECT id, owner_id, object_key, original_name, mime_type, width, height, size, sha256, status, created_at, updated_at, completed_at FROM media_assets WHERE id = \$1 AND deleted_at IS NULL`).
		WithArgs("media-race").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "owner_id", "object_key", "original_name", "mime_type", "width", "height", "size", "sha256", "status", "created_at", "updated_at", "completed_at",
		}).AddRow("media-race", "user-1", objectKey, "race.jpg", "image/jpeg", 2, 2, int64(len(rawBytes)), digestHex, "pending", createdAt, createdAt, nil))
	mock.ExpectBegin()
	mock.ExpectExec(`UPDATE media_assets SET status = 'ready'`).
		WithArgs(2, 2, sqlmock.AnyArg(), "media-race", "user-1").
		WillReturnResult(sqlmock.NewResult(1, 0))
	completedAt := createdAt.Add(time.Minute)
	mock.ExpectQuery(`SELECT status, width, height, updated_at, completed_at FROM media_assets WHERE id = \$1 AND owner_id = \$2 AND deleted_at IS NULL`).
		WithArgs("media-race", "user-1").
		WillReturnRows(sqlmock.NewRows([]string{"status", "width", "height", "updated_at", "completed_at"}).
			AddRow("ready", 2, 2, completedAt, completedAt))
	mock.ExpectRollback()

	req := httptest.NewRequest(http.MethodPost, "/api/v1/media/media-race/complete", nil)
	req = req.WithContext(context.WithValue(req.Context(), authenticatedUserContextKey{}, auth.User{ID: "user-1", AccountType: "email"}))
	rec := httptest.NewRecorder()
	(&Server{db: db, mediaStorage: store}).completeMedia(rec, req, "media-race")

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s, want idempotent 200", rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"status":"ready"`)) {
		t.Fatalf("response=%s, want ready media", rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unexpected concurrent complete SQL: %v", err)
	}
}
