package api

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

// seekableReadCloser 让内存对象支持 http.ServeContent 的 Range/条件请求路径。
type seekableReadCloser struct {
	*bytes.Reader
}

func (s *seekableReadCloser) Close() error { return nil }

// seekableMemoryStorage 返回可 Seek 的读取器，模拟本地文件存储行为。
type seekableMemoryStorage struct {
	*storage.MemoryStorage
}

func (s *seekableMemoryStorage) Get(_ context.Context, objectKey string) (io.ReadCloser, int64, string, error) {
	data, ok := s.GetBytes(objectKey)
	if !ok {
		return nil, 0, "", storage.ErrObjectNotFound
	}
	return &seekableReadCloser{bytes.NewReader(data)}, int64(len(data)), "image/jpeg", nil
}

func newGatewayTestServer(t *testing.T, mode string) (*Server, sqlmock.Sqlmock, *storage.MemoryStorage) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	store := storage.NewMemoryStorage()
	return &Server{db: db, mediaStorage: store, mediaDeliveryMode: mode}, mock, store
}

func expectGatewayVariantRow(mock sqlmock.Sqlmock, mediaID, variant, mimeType, moderationStatus, objectKey string) {
	mock.ExpectQuery(`(?s)SELECT ma\.mime_type.*JOIN media_variants mv`).
		WithArgs(mediaID, variant).
		WillReturnRows(sqlmock.NewRows([]string{"mime_type", "moderation_status", "object_key"}).
			AddRow(mimeType, moderationStatus, objectKey))
}

func TestGatewayMediaVariantServesPublicVariantOfPublishedPost(t *testing.T) {
	s, mock, store := newGatewayTestServer(t, "gateway")
	payload := []byte("variant-bytes")
	key := "media/u-1/media_abc_detail.jpg"
	if err := store.Put(context.Background(), key, "image/jpeg", bytes.NewReader(payload), int64(len(payload))); err != nil {
		t.Fatal(err)
	}
	expectGatewayVariantRow(mock, "media_abc", "detail", "image/jpeg", "normal", key)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media_abc/detail", nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, "media_abc/detail")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if !bytes.Equal(rec.Body.Bytes(), payload) {
		t.Fatalf("body mismatch: %q", rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "private, no-store" {
		t.Fatalf("Cache-Control = %q, want private, no-store for normal variants", got)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestGatewayMediaVariantRejectsPendingPost(t *testing.T) {
	s, mock, _ := newGatewayTestServer(t, "gateway")
	mock.ExpectQuery(`(?s)SELECT ma\.mime_type.*JOIN media_variants mv.*p\.moderation_status = 'normal'`).
		WithArgs("media_pending_post", "detail").
		WillReturnRows(sqlmock.NewRows([]string{"mime_type", "moderation_status", "object_key"}))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media_pending_post/detail", nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, "media_pending_post/detail")

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 for pending post media", rec.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestGatewayMediaVariantRejectsPendingComment(t *testing.T) {
	s, mock, _ := newGatewayTestServer(t, "gateway")
	mock.ExpectQuery(`(?s)SELECT ma\.mime_type.*JOIN media_variants mv.*c\.moderation_status = 'normal'`).
		WithArgs("media_pending_comment", "detail").
		WillReturnRows(sqlmock.NewRows([]string{"mime_type", "moderation_status", "object_key"}))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media_pending_comment/detail", nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, "media_pending_comment/detail")

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 for pending comment media", rec.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestGatewayMediaVariantServesCensoredVariantWithImmutableCache(t *testing.T) {
	s, mock, store := newGatewayTestServer(t, "gateway")
	key := "media/u-1/media_abc_censored_beef_thumb.jpg"
	if err := store.Put(context.Background(), key, "image/jpeg", bytes.NewReader([]byte("masked")), 7); err != nil {
		t.Fatal(err)
	}
	expectGatewayVariantRow(mock, "media_abc", "censored_thumb", "image/jpeg", "censored", key)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media_abc/censored_thumb", nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, "media_abc/censored_thumb")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := rec.Header().Get("Cache-Control"); got != "public, max-age=31536000, immutable" {
		t.Fatalf("Cache-Control = %q, want immutable for censored variants", got)
	}
}

func TestGatewayMediaVariantRejectsSourceOfImage(t *testing.T) {
	s, mock, _ := newGatewayTestServer(t, "gateway")
	expectGatewayVariantRow(mock, "media_abc", "source", "image/jpeg", "normal", "media/u-1/media_abc")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media_abc/source", nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, "media_abc/source")

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 for image source via gateway", rec.Code)
	}
}

func TestGatewayMediaVariantAllowsVideoSource(t *testing.T) {
	s, mock, store := newGatewayTestServer(t, "gateway")
	key := "media/u-1/media_vid"
	if err := store.Put(context.Background(), key, "video/mp4", bytes.NewReader([]byte("mp4")), 3); err != nil {
		t.Fatal(err)
	}
	expectGatewayVariantRow(mock, "media_vid", "source", "video/mp4", "normal", key)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media_vid/source", nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, "media_vid/source")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 for video source", rec.Code)
	}
}

func TestGatewayMediaVariantRejectsUnknownVariantName(t *testing.T) {
	s, _, _ := newGatewayTestServer(t, "gateway")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media_abc/evil", nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, "media_abc/evil")

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 without DB lookup", rec.Code)
	}
}

func TestGatewayMediaVariantMissingOrHiddenResourceIs404(t *testing.T) {
	s, mock, _ := newGatewayTestServer(t, "gateway")
	// 媒体不存在 / 已删除 / 非 ready / 资源不可见，在 SQL 层统一表现为无行。
	mock.ExpectQuery(`(?s)SELECT ma\.mime_type.*JOIN media_variants mv`).
		WithArgs("media_gone", "thumb").
		WillReturnRows(sqlmock.NewRows([]string{"mime_type", "moderation_status", "object_key"}))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media_gone/thumb", nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, "media_gone/thumb")

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
}

func TestGatewayObjectKeyBlocksProcessedSource(t *testing.T) {
	s, mock, _ := newGatewayTestServer(t, "gateway")
	key := "media/u-1/media_abc"
	mock.ExpectQuery(`(?s)SELECT ma\.mime_type.*COALESCE\(\(SELECT mv\.variant`).
		WithArgs(key).
		WillReturnRows(sqlmock.NewRows([]string{"mime_type", "moderation_status", "variant_name", "has_processed"}).
			AddRow("image/jpeg", "normal", "", true))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/"+key, nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, key)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 for processed image source in gateway mode", rec.Code)
	}
}

func TestGatewayObjectKeyBlocksUnprocessedSource(t *testing.T) {
	s, mock, store := newGatewayTestServer(t, "gateway")
	key := "media/u-1/media_legacy"
	if err := store.Put(context.Background(), key, "image/jpeg", bytes.NewReader([]byte("legacy")), 6); err != nil {
		t.Fatal(err)
	}
	mock.ExpectQuery(`(?s)SELECT ma\.mime_type.*COALESCE\(\(SELECT mv\.variant`).
		WithArgs(key).
		WillReturnRows(sqlmock.NewRows([]string{"mime_type", "moderation_status", "variant_name", "has_processed"}).
			AddRow("image/jpeg", "normal", "", false))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/"+key, nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, key)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 for unprocessed image source", rec.Code)
	}
}

func TestGatewayObjectKeyBlocksCensoredSourceAndNormalVariants(t *testing.T) {
	s, mock, _ := newGatewayTestServer(t, "gateway")
	sourceKey := "media/u-1/media_sens"
	mock.ExpectQuery(`(?s)SELECT ma\.mime_type.*COALESCE\(\(SELECT mv\.variant`).
		WithArgs(sourceKey).
		WillReturnRows(sqlmock.NewRows([]string{"mime_type", "moderation_status", "variant_name", "has_processed"}).
			AddRow("image/jpeg", "censored", "", false))
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/"+sourceKey, nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, sourceKey)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 for censored source", rec.Code)
	}

	normalVariantKey := "media/u-1/media_sens_thumb.jpg"
	mock.ExpectQuery(`(?s)SELECT ma\.mime_type.*COALESCE\(\(SELECT mv\.variant`).
		WithArgs(normalVariantKey).
		WillReturnRows(sqlmock.NewRows([]string{"mime_type", "moderation_status", "variant_name", "has_processed"}).
			AddRow("image/jpeg", "censored", "thumb", false))
	req2 := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/"+normalVariantKey, nil)
	rec2 := httptest.NewRecorder()
	s.serveMediaFile(rec2, req2, normalVariantKey)
	if rec2.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 for normal variant of censored media", rec2.Code)
	}
}

func TestGatewayObjectKeyServesCensoredVariant(t *testing.T) {
	s, mock, store := newGatewayTestServer(t, "gateway")
	key := "media/u-1/media_sens_censored_beef_detail.jpg"
	if err := store.Put(context.Background(), key, "image/jpeg", bytes.NewReader([]byte("masked")), 6); err != nil {
		t.Fatal(err)
	}
	mock.ExpectQuery(`(?s)SELECT ma\.mime_type.*COALESCE\(\(SELECT mv\.variant`).
		WithArgs(key).
		WillReturnRows(sqlmock.NewRows([]string{"mime_type", "moderation_status", "variant_name", "has_processed"}).
			AddRow("image/jpeg", "censored", "censored_detail", false))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/"+key, nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, key)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := rec.Header().Get("Cache-Control"); got != "public, max-age=31536000, immutable" {
		t.Fatalf("Cache-Control = %q, want immutable", got)
	}
}

func TestDirectModeKeepsBlacklistBehavior(t *testing.T) {
	s, mock, store := newGatewayTestServer(t, "direct")
	key := "media/u-1/media_normal.jpg"
	if err := store.Put(context.Background(), key, "image/jpeg", bytes.NewReader([]byte("raw")), 3); err != nil {
		t.Fatal(err)
	}
	mock.ExpectQuery(`(?s)SELECT.*EXISTS.*FROM media_assets.*media_variants`).
		WithArgs(key).
		WillReturnRows(sqlmock.NewRows([]string{"is_public_media", "is_censored_raw", "managed_source"}).AddRow(true, false, true))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/"+key, nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, key)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 in direct mode", rec.Code)
	}
	if got := rec.Header().Get("Cache-Control"); got != "private, no-store" {
		t.Fatalf("Cache-Control = %q, want private, no-store for managed source", got)
	}
}

func TestDirectModeRejectsPendingPostMedia(t *testing.T) {
	s, mock, _ := newGatewayTestServer(t, "direct")
	key := "media/u-1/media_pending.jpg"
	mock.ExpectQuery(`(?s)SELECT.*p\.moderation_status = 'normal'.*media_variants`).
		WithArgs(key).
		WillReturnRows(sqlmock.NewRows([]string{"is_public_media", "is_censored_raw", "managed_source"}).AddRow(false, false, true))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/"+key, nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, key)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 for pending media in direct mode", rec.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestGatewayAccelRedirectSkipsStorage(t *testing.T) {
	s, mock, _ := newGatewayTestServer(t, "gateway")
	s.mediaAccelPrefix = "/_protected_media"
	// 故意不写入对象：若实现误回退为进程内拉流，Get 将 404 导致用例失败。
	expectGatewayVariantRow(mock, "media_abc", "detail", "image/jpeg", "normal", "media/u-1/media_abc_detail.jpg")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media_abc/detail", nil)
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, "media_abc/detail")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 with X-Accel-Redirect", rec.Code)
	}
	if got := rec.Header().Get("X-Accel-Redirect"); got != "/_protected_media/media/u-1/media_abc_detail.jpg" {
		t.Fatalf("X-Accel-Redirect = %q", got)
	}
	if rec.Body.Len() != 0 {
		t.Fatalf("accel response should carry no body, got %d bytes", rec.Body.Len())
	}
}

func TestMediaFileRangeRequest(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	store := &seekableMemoryStorage{MemoryStorage: storage.NewMemoryStorage()}
	payload := []byte("0123456789")
	if err := store.Put(context.Background(), "media/u-1/media-1", "image/jpeg", bytes.NewReader(payload), int64(len(payload))); err != nil {
		t.Fatal(err)
	}
	_ = mock

	s := &Server{mediaStorage: store}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media/u-1/media-1", nil)
	req.Header.Set("Range", "bytes=0-3")
	rec := httptest.NewRecorder()
	s.serveMediaFile(rec, req, "media/u-1/media-1")

	if rec.Code != http.StatusPartialContent {
		t.Fatalf("status = %d, want 206 for ranged GET", rec.Code)
	}
	if !bytes.Equal(rec.Body.Bytes(), payload[:4]) {
		t.Fatalf("ranged body = %q, want %q", rec.Body.String(), "0123")
	}
}

func TestGetAdminMediaSourceRejectsAnonymous(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	s := &Server{db: db, mediaStorage: storage.NewMemoryStorage()}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/media/media-1/source", nil)
	rec := httptest.NewRecorder()
	s.getAdminMediaSource(rec, req, "media-1")

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 for anonymous admin source access", rec.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("admin source must not touch media rows before auth: %v", err)
	}
}

func TestGetAdminMediaPreviewRejectsAnonymous(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	s := &Server{db: db, mediaStorage: storage.NewMemoryStorage()}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/media/media-1/preview", nil)
	rec := httptest.NewRecorder()
	s.getAdminMediaPreview(rec, req, "media-1")

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 for anonymous admin preview access", rec.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("admin preview must not touch media rows before auth: %v", err)
	}
}

func TestGetAdminMediaPreviewUsesPrivateDetailVariant(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	store := storage.NewMemoryStorage()
	if err := store.Put(context.Background(), "media/u-1/m-detail", "image/jpeg", bytes.NewReader([]byte("detail")), 6); err != nil {
		t.Fatal(err)
	}
	s := &Server{db: db, mediaStorage: store}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/media/m-1/preview", nil)
	req = req.WithContext(context.WithValue(req.Context(), authenticatedUserContextKey{}, auth.User{ID: "admin-1"}))

	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*p\.name = \$2.*community_id IS NULL`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))
	mock.ExpectQuery(`(?s)SELECT COALESCE\(preferred\.object_key.*FROM media_assets ma.*LEFT JOIN LATERAL`).
		WithArgs("m-1").
		WillReturnRows(sqlmock.NewRows([]string{"object_key", "mime_type", "moderation_status"}).
			AddRow("media/u-1/m-detail", "image/jpeg", "normal"))

	rec := httptest.NewRecorder()
	s.getAdminMediaPreview(rec, req, "m-1")
	if rec.Code != http.StatusOK || rec.Body.String() != "detail" {
		t.Fatalf("preview response: status=%d body=%q", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "private, no-store" {
		t.Fatalf("Cache-Control = %q, want private, no-store", got)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestParseGatewayMediaPath(t *testing.T) {
	cases := []struct {
		rest        string
		wantID      string
		wantVariant string
		wantOK      bool
	}{
		{"media_abc123/detail", "media_abc123", "detail", true},
		{"media_abc123/censored_thumb", "media_abc123", "censored_thumb", true},
		{"media_abc123/evil", "", "", false},
		{"media/user-1/media-1", "", "", false},
		{"imported-media/post.webp", "", "", false},
		{"media_abc123", "", "", false},
		{"media_/detail", "", "", false},
		{"media_abc123/detail/extra", "", "", false},
	}
	for _, tc := range cases {
		id, variant, ok := parseGatewayMediaPath(tc.rest)
		if ok != tc.wantOK || id != tc.wantID || variant != tc.wantVariant {
			t.Errorf("parseGatewayMediaPath(%q) = (%q, %q, %v), want (%q, %q, %v)",
				tc.rest, id, variant, ok, tc.wantID, tc.wantVariant, tc.wantOK)
		}
	}
}

func TestMediaCacheControlPolicy(t *testing.T) {
	if got := mediaCacheControl("censored", "censored_thumb"); got != "public, max-age=31536000, immutable" {
		t.Fatalf("censored variant cache = %q", got)
	}
	if got := mediaCacheControl("normal", "thumb"); got != "private, no-store" {
		t.Fatalf("normal variant cache = %q", got)
	}
	if !strings.HasPrefix(mediaCacheControl("normal", "source"), "private") {
		t.Fatalf("source cache = %q", mediaCacheControl("normal", "source"))
	}
}
