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
	if !strings.Contains(res.Body.String(), `"status":"ok"`) {
		t.Fatalf("health body = %s", res.Body.String())
	}
}

func TestMetricsEndpointExposesPrometheusShape(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	res := httptest.NewRecorder()
	NewHandler(nil, slog.New(slog.NewTextHandler(io.Discard, nil))).ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), "luntan_http_requests_total") || !strings.Contains(res.Body.String(), "quantile=\"0.95\"") {
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
