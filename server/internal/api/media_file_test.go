package api

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

func newMediaFileTestServer(t *testing.T) *Server {
	t.Helper()
	return &Server{mediaStorage: storage.NewMemoryStorage()}
}

func TestServeMediaFileReturnsObjectWithImmutableCache(t *testing.T) {
	s := newMediaFileTestServer(t)
	payload := []byte("fake-png-bytes")
	if err := s.mediaStorage.Put(context.Background(), "media/user-1/media-1", "image/png", bytes.NewReader(payload), int64(len(payload))); err != nil {
		t.Fatalf("seed object: %v", err)
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media/user-1/media-1", nil)
	s.serveMediaFile(rec, req, "media/user-1/media-1")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := rec.Header().Get("Cache-Control"); got != "public, max-age=31536000, immutable" {
		t.Fatalf("Cache-Control = %q, want immutable year-long policy", got)
	}
	if got := rec.Header().Get("Content-Type"); got != "image/png" {
		t.Fatalf("Content-Type = %q, want image/png", got)
	}
	if !bytes.Equal(rec.Body.Bytes(), payload) {
		t.Fatalf("body mismatch: got %q", rec.Body.String())
	}
}

func TestServeMediaFileHeadWithoutBody(t *testing.T) {
	s := newMediaFileTestServer(t)
	payload := []byte("fake-png-bytes")
	if err := s.mediaStorage.Put(context.Background(), "media/user-1/media-1", "image/png", bytes.NewReader(payload), int64(len(payload))); err != nil {
		t.Fatalf("seed object: %v", err)
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodHead, "/api/v1/media-file/media/user-1/media-1", nil)
	s.serveMediaFile(rec, req, "media/user-1/media-1")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if rec.Body.Len() != 0 {
		t.Fatalf("HEAD response should have no body, got %d bytes", rec.Body.Len())
	}
}

func TestServeMediaFileNotFound(t *testing.T) {
	s := newMediaFileTestServer(t)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media/user-1/missing", nil)
	s.serveMediaFile(rec, req, "media/user-1/missing")

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
}

func TestServeMediaFileRejectsUncensoredVariantWhenAssetIsCensored(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	store := storage.NewMemoryStorage()
	objectKey := "media/user-1/media-1_original.jpg"
	if err := store.Put(context.Background(), objectKey, "image/jpeg", bytes.NewReader([]byte("raw")), 3); err != nil {
		t.Fatal(err)
	}
	mock.ExpectQuery(`(?s)SELECT.*EXISTS.*FROM media_assets.*media_variants`).
		WithArgs(objectKey).
		WillReturnRows(sqlmock.NewRows([]string{"is_public_media", "is_censored_raw", "managed_source"}).AddRow(true, true, true))

	s := &Server{db: db, mediaStorage: store}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/"+objectKey, nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, objectKey)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 for an uncensored variant of a censored asset", rec.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestServeMediaFileRejectsPathTraversal(t *testing.T) {
	s := newMediaFileTestServer(t)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/../secrets", nil)
	s.serveMediaFile(rec, req, "../secrets")

	// 路径穿越必须被拒绝：本地存储在 objectPath 清洗后返回 400，
	// 内存存储按 key 查找未命中返回 404；任何情况下都不能 200。
	if rec.Code != http.StatusBadRequest && rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 400 or 404", rec.Code)
	}
}

func TestGetAdminMediaSourceIsPrivateAndNoStore(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	store := storage.NewMemoryStorage()
	payload := []byte("private-source")
	if err := store.Put(context.Background(), "media/user-1/media-1", "image/jpeg", bytes.NewReader(payload), int64(len(payload))); err != nil {
		t.Fatal(err)
	}
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))
	mock.ExpectQuery(`SELECT object_key, mime_type FROM media_assets WHERE id = \$1 AND deleted_at IS NULL`).
		WithArgs("media-1").
		WillReturnRows(sqlmock.NewRows([]string{"object_key", "mime_type"}).AddRow("media/user-1/media-1", "image/jpeg"))

	s := &Server{db: db, mediaStorage: store}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/media/media-1/source", nil)
	req = req.WithContext(context.WithValue(req.Context(), authenticatedUserContextKey{}, auth.User{ID: "admin-1"}))
	rec := httptest.NewRecorder()
	s.getAdminMediaSource(rec, req, "media-1")

	if rec.Code != http.StatusOK || !bytes.Equal(rec.Body.Bytes(), payload) {
		t.Fatalf("source response status=%d body=%q", rec.Code, rec.Body.Bytes())
	}
	if got := rec.Header().Get("Cache-Control"); got != "private, no-store" {
		t.Fatalf("Cache-Control=%q, want private, no-store", got)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestPublicMediaURLFallbacks(t *testing.T) {
	t.Setenv("OBJECT_STORAGE_PUBLIC_BASE_URL", "")
	if got := publicMediaURL("media/user-1/media-1"); got != "/api/v1/media-file/media/user-1/media-1" {
		t.Fatalf("fallback url = %q, want media-file route", got)
	}
	t.Setenv("OBJECT_STORAGE_PUBLIC_BASE_URL", "https://cdn.example.com")
	if got := publicMediaURL("media/user-1/media-1"); got != "/api/v1/media-file/media/user-1/media-1" {
		t.Fatalf("uploaded media url = %q, want application media route", got)
	}
	if got := publicMediaURL("https://legacy.example.com/a.png"); got != "https://legacy.example.com/a.png" {
		t.Fatalf("absolute passthrough = %q, want unchanged", got)
	}
}
