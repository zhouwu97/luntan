package httpserver

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealth(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	res := httptest.NewRecorder()
	NewHandler(nil, slog.New(slog.NewTextHandler(io.Discard, nil))).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("health status = %d, want 200", res.Code)
	}
	if !strings.Contains(res.Body.String(), `"status":"ok"`) || !strings.Contains(res.Body.String(), `"version":"dev"`) || !strings.Contains(res.Body.String(), `"commit":"unknown"`) {
		t.Fatalf("health body = %s", res.Body.String())
	}
	if res.Header().Get("Access-Control-Allow-Origin") != "*" {
		t.Fatalf("cors header = %q, want wildcard", res.Header().Get("Access-Control-Allow-Origin"))
	}
}

func TestCORSPreflight(t *testing.T) {
	req := httptest.NewRequest(http.MethodOptions, "/api/v1/feed/latest", nil)
	req.Header.Set("Origin", "http://localhost:4173")
	req.Header.Set("Access-Control-Request-Method", http.MethodGet)
	res := httptest.NewRecorder()
	NewHandler(nil, slog.New(slog.NewTextHandler(io.Discard, nil))).ServeHTTP(res, req)

	if res.Code != http.StatusNoContent {
		t.Fatalf("preflight status = %d, want 204", res.Code)
	}
	if res.Header().Get("Access-Control-Allow-Headers") == "" {
		t.Fatal("preflight allow headers are empty")
	}
	if !strings.Contains(res.Header().Get("Access-Control-Allow-Headers"), "X-App-Version-Code") {
		t.Fatal("preflight allow headers must include app update version headers")
	}
}

func TestConfiguredCORSAllowsCredentialsOnlyForMatchingOrigin(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	handler, err := NewHandlerWithAPIOptions(nil, logger, nil, Options{
		AllowedOrigin: "https://app.example.com",
	})
	if err != nil {
		t.Fatalf("create handler: %v", err)
	}

	allowedReq := httptest.NewRequest(http.MethodGet, "/health", nil)
	allowedReq.Header.Set("Origin", "https://app.example.com")
	allowedRes := httptest.NewRecorder()
	handler.ServeHTTP(allowedRes, allowedReq)
	if allowedRes.Header().Get("Access-Control-Allow-Origin") != "https://app.example.com" {
		t.Fatalf("allowed origin = %q", allowedRes.Header().Get("Access-Control-Allow-Origin"))
	}
	if allowedRes.Header().Get("Access-Control-Allow-Credentials") != "true" {
		t.Fatalf("allowed credentials = %q, want true", allowedRes.Header().Get("Access-Control-Allow-Credentials"))
	}

	otherReq := httptest.NewRequest(http.MethodGet, "/health", nil)
	otherReq.Header.Set("Origin", "https://other.example.com")
	otherRes := httptest.NewRecorder()
	handler.ServeHTTP(otherRes, otherReq)
	if otherRes.Header().Get("Access-Control-Allow-Origin") != "*" {
		t.Fatalf("other origin = %q, want wildcard", otherRes.Header().Get("Access-Control-Allow-Origin"))
	}
	if otherRes.Header().Get("Access-Control-Allow-Credentials") != "" {
		t.Fatalf("other credentials = %q, want empty", otherRes.Header().Get("Access-Control-Allow-Credentials"))
	}
}

func TestVersion(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/version", nil)
	res := httptest.NewRecorder()
	NewHandler(nil, slog.New(slog.NewTextHandler(io.Discard, nil))).ServeHTTP(res, req)

	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"status":"ok"`) {
		t.Fatalf("version response: status=%d body=%s", res.Code, res.Body.String())
	}
}

func TestMetricsEndpointExposesPrometheusShape(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	res := httptest.NewRecorder()
	NewHandler(nil, slog.New(slog.NewTextHandler(io.Discard, nil))).ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), "luntan_http_requests_total") || !strings.Contains(res.Body.String(), "quantile=\"0.95\"") || !strings.Contains(res.Body.String(), "luntan_login_success_rate") {
		t.Fatalf("metrics response: status=%d body=%s", res.Code, res.Body.String())
	}
}

func TestUnknownRouteReturnsStandardErrorAndRequestID(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/unknown", nil)
	res := httptest.NewRecorder()
	NewHandler(nil, slog.New(slog.NewTextHandler(io.Discard, nil))).ServeHTTP(res, req)

	if res.Code != http.StatusNotFound {
		t.Fatalf("unknown status = %d, want 404", res.Code)
	}
	if res.Header().Get("X-Request-ID") == "" {
		t.Fatal("X-Request-ID header is empty")
	}
	var payload map[string]any
	if err := json.Unmarshal(res.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode error response: %v", err)
	}
	if payload["code"] != "NOT_FOUND" || payload["details"] != nil {
		t.Fatalf("unexpected error payload: %#v", payload)
	}
}

func TestReadyWithoutDatabaseReturns503(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/ready", nil)
	res := httptest.NewRecorder()
	NewHandler(nil, slog.New(slog.NewTextHandler(io.Discard, nil))).ServeHTTP(res, req)
	if res.Code != http.StatusServiceUnavailable {
		t.Fatalf("ready status = %d, want 503", res.Code)
	}
}

func TestPanicReturnsStandard500(t *testing.T) {
	handler := requestIDMiddleware(recoveryMiddleware(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { panic("boom") })))
	req := httptest.NewRequest(http.MethodGet, "/panic", nil)
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusInternalServerError {
		t.Fatalf("panic status = %d, want 500", res.Code)
	}
	if !strings.Contains(res.Body.String(), `"code":"INTERNAL_ERROR"`) {
		t.Fatalf("panic body = %s", res.Body.String())
	}
}

func TestRateLimiterPreservesRouteBucketAcrossRequests(t *testing.T) {
	t.Setenv("RATE_LIMIT_ENABLED", "true")
	apiHandler := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	})
	handler := NewHandlerWithAPI(nil, slog.New(slog.NewTextHandler(io.Discard, nil)), apiHandler)
	for index := 0; index < 10; index++ {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(`{"username":"user","password":"password123"}`))
		req.RemoteAddr = "198.51.100.10:1234"
		res := httptest.NewRecorder()
		handler.ServeHTTP(res, req)
		if res.Code != http.StatusServiceUnavailable {
			t.Fatalf("request %d status = %d, want 503 before limit", index+1, res.Code)
		}
	}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader(`{"username":"user","password":"password123"}`))
	req.RemoteAddr = "198.51.100.10:1234"
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusTooManyRequests || !strings.Contains(res.Body.String(), `"code":"RATE_LIMITED"`) {
		t.Fatalf("limited response: status=%d body=%s", res.Code, res.Body.String())
	}
}
