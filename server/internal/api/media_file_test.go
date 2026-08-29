package api

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

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

func TestPublicMediaURLFallbacks(t *testing.T) {
	t.Setenv("OBJECT_STORAGE_PUBLIC_BASE_URL", "")
	if got := publicMediaURL("media/user-1/media-1"); got != "/api/v1/media-file/media/user-1/media-1" {
		t.Fatalf("fallback url = %q, want media-file route", got)
	}
	t.Setenv("OBJECT_STORAGE_PUBLIC_BASE_URL", "https://cdn.example.com")
	if got := publicMediaURL("media/user-1/media-1"); got != "https://cdn.example.com/media/user-1/media-1" {
		t.Fatalf("cdn url = %q, want cdn base joined", got)
	}
	if got := publicMediaURL("https://legacy.example.com/a.png"); got != "https://legacy.example.com/a.png" {
		t.Fatalf("absolute passthrough = %q, want unchanged", got)
	}
}
