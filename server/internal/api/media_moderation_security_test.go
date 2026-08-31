package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/media"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

type failModerationPutStorage struct {
	*storage.MemoryStorage
}

func (s *failModerationPutStorage) Put(ctx context.Context, objectKey, mimeType string, reader io.Reader, size int64) error {
	if strings.HasSuffix(objectKey, "_detail.jpg") {
		return errors.New("injected detail variant storage failure")
	}
	return s.MemoryStorage.Put(ctx, objectKey, mimeType, reader, size)
}

func moderationTestJPEG() []byte {
	img := image.NewRGBA(image.Rect(0, 0, 80, 60))
	for y := 0; y < 60; y++ {
		for x := 0; x < 80; x++ {
			img.SetRGBA(x, y, color.RGBA{R: uint8(x * 3), G: uint8(y * 4), B: 100, A: 255})
		}
	}
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 90})
	return buf.Bytes()
}

func moderationRequest(body string) *http.Request {
	req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/media/media-1/moderation", strings.NewReader(body))
	return req.WithContext(context.WithValue(req.Context(), authenticatedUserContextKey{}, auth.User{
		ID: "admin-1", AccountType: "email", Status: "active",
	}))
}

func expectModerationPermission(mock sqlmock.Sqlmock) {
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))
}

func expectModerationMedia(mock sqlmock.Sqlmock, objectKey, mimeType string) {
	mock.ExpectQuery(`(?s)SELECT object_key, mime_type, status FROM media_assets WHERE id = \$1 AND deleted_at IS NULL`).
		WithArgs("media-1").
		WillReturnRows(sqlmock.NewRows([]string{"object_key", "mime_type", "status"}).
			AddRow(objectKey, mimeType, "ready"))
}

func TestModerateMediaRejectsCensoredWithoutMaskRegions(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	expectModerationPermission(mock)

	server := &Server{db: db, mediaStorage: storage.NewMemoryStorage()}
	rec := httptest.NewRecorder()
	server.moderateMedia(rec, moderationRequest(`{"moderation_status":"censored","mask_regions":[]}`), "media-1")

	if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), `"code":"MASK_REGIONS_REQUIRED"`) {
		t.Fatalf("expected mask regions validation error, status=%d body=%s", rec.Code, rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unexpected database access after validation: %v", err)
	}
}

func TestModerateMediaRejectsInvalidMaskRegion(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	expectModerationPermission(mock)

	server := &Server{db: db, mediaStorage: storage.NewMemoryStorage()}
	rec := httptest.NewRecorder()
	server.moderateMedia(rec, moderationRequest(`{"moderation_status":"censored","mask_regions":[{"x":0.9,"y":0.1,"width":0.2,"height":0.2,"type":"mosaic"}]}`), "media-1")

	if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), `"code":"INVALID_MASK_REGION"`) {
		t.Fatalf("expected invalid mask region error, status=%d body=%s", rec.Code, rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unexpected database access after validation: %v", err)
	}
}

func TestModerateMediaStorageFailureLeavesDatabaseUntouched(t *testing.T) {
	const objectKey = "media/user-1/media-1"
	source := moderationTestJPEG()
	store := &failModerationPutStorage{MemoryStorage: storage.NewMemoryStorage()}
	if err := store.Put(context.Background(), objectKey, "image/jpeg", bytes.NewReader(source), int64(len(source))); err != nil {
		t.Fatal(err)
	}

	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	expectModerationPermission(mock)
	expectModerationMedia(mock, objectKey, "image/jpeg")

	server := &Server{db: db, mediaStorage: store}
	regions := []media.MaskRegion{{X: 0.1, Y: 0.1, Width: 0.5, Height: 0.5, Type: "mosaic"}}
	rec := httptest.NewRecorder()
	body, _ := json.Marshal(map[string]any{"moderation_status": "censored", "mask_regions": regions})
	server.moderateMedia(rec, moderationRequest(string(body)), "media-1")

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 after variant storage failure, got %d body=%s", rec.Code, rec.Body.String())
	}
	if !store.HasObject(objectKey) {
		t.Fatal("source image should remain available after failed moderation")
	}
	regionsJSON, _ := json.Marshal(regions)
	maskHash := sha256.Sum256(regionsJSON)
	if _, ok := store.GetBytes(objectKey + "_censored_" + hex.EncodeToString(maskHash[:])[:8] + "_original.jpg"); ok {
		t.Fatal("successful original variant should be cleaned up after detail failure")
	}
	if _, ok := store.GetBytes(objectKey + "_censored_" + hex.EncodeToString(maskHash[:])[:8] + "_detail.jpg"); ok {
		t.Fatal("failed detail variant should not be persisted")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("database should not be modified after storage failure: %v", err)
	}
}

func TestProcessCensoredImageRejectsRegionsThatCoverNoPixels(t *testing.T) {
	_, err := media.ProcessCensoredImage(bytes.NewReader(moderationTestJPEG()), []media.MaskRegion{{
		X: 0.1, Y: 0.1, Width: 0.0001, Height: 0.0001, Type: "mosaic",
	}})
	if err == nil {
		t.Fatal("expected processing to fail when no region reaches a source pixel")
	}
}
