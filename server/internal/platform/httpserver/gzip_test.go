package httpserver

import (
	"compress/gzip"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newSilentHandler() http.Handler {
	return NewHandler(nil, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func TestGzipCompressesJSONResponses(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("Accept-Encoding", "gzip")
	res := httptest.NewRecorder()
	newSilentHandler().ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", res.Code)
	}
	if res.Header().Get("Content-Encoding") != "gzip" {
		t.Fatalf("Content-Encoding = %q, want gzip", res.Header().Get("Content-Encoding"))
	}
	vary := strings.Join(res.Header().Values("Vary"), ", ")
	if !strings.Contains(vary, "Accept-Encoding") || !strings.Contains(vary, "Origin") {
		t.Fatalf("Vary = %q, want both Accept-Encoding and Origin", vary)
	}
	reader, err := gzip.NewReader(res.Body)
	if err != nil {
		t.Fatalf("response body is not valid gzip: %v", err)
	}
	defer reader.Close()
	body, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("read gzip body: %v", err)
	}
	if !strings.Contains(string(body), `"status":"ok"`) {
		t.Fatalf("decompressed body = %s", string(body))
	}
}

func TestGzipSkippedWhenClientDoesNotAcceptGzip(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	res := httptest.NewRecorder()
	newSilentHandler().ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", res.Code)
	}
	if res.Header().Get("Content-Encoding") != "" {
		t.Fatalf("Content-Encoding = %q, want empty", res.Header().Get("Content-Encoding"))
	}
	if !strings.Contains(res.Body.String(), `"status":"ok"`) {
		t.Fatalf("plain body = %s", res.Body.String())
	}
}

func TestGzipSkippedForMediaFileRoute(t *testing.T) {
	// /health 是 JSON；这里用一个独立 handler 直接验证 gzipResponseWriter
	// 对 media-file 路径的处理逻辑（真实 media-file 路由依赖数据库与存储）。
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/octet-stream")
		_, _ = w.Write([]byte("fake media bytes"))
	})
	handler := gzipMiddleware(next)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media/u1/m1", nil)
	req.Header.Set("Accept-Encoding", "gzip")
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)

	if res.Header().Get("Content-Encoding") == "gzip" {
		t.Fatal("media-file response must not be gzipped")
	}
	if res.Body.String() != "fake media bytes" {
		t.Fatalf("media body = %q", res.Body.String())
	}
}

func TestGzipSkippedForNonJSONContentType(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		_, _ = w.Write([]byte("metrics_body"))
	})
	handler := gzipMiddleware(next)

	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	req.Header.Set("Accept-Encoding", "gzip")
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)

	if res.Header().Get("Content-Encoding") != "" {
		t.Fatalf("Content-Encoding = %q, want empty for text/plain", res.Header().Get("Content-Encoding"))
	}
	if res.Body.String() != "metrics_body" {
		t.Fatalf("metrics body = %q", res.Body.String())
	}
}
