package httpserver

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"time"
)

type contextKey string

const requestIDKey contextKey = "request_id"

type AppError struct {
	Status  int
	Code    string
	Message string
	Details any
}

func (e AppError) Error() string { return e.Code }

func NewHandler(db *sql.DB, logger *slog.Logger) http.Handler {
	if logger == nil {
		logger = slog.Default()
	}
	router := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/health":
			writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		case r.Method == http.MethodGet && r.URL.Path == "/ready":
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			defer cancel()
			if err := pingDatabase(ctx, db); err != nil {
				writeAppError(w, r, AppError{Status: http.StatusServiceUnavailable, Code: "DATABASE_UNAVAILABLE", Message: "服务暂时不可用"})
				return
			}
			writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
		default:
			writeAppError(w, r, AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "请求资源不存在"})
		}
	})
	return requestIDMiddleware(loggingMiddleware(recoveryMiddleware(router), logger))
}

func pingDatabase(ctx context.Context, db *sql.DB) error {
	if db == nil {
		return fmt.Errorf("database is not configured")
	}
	return db.PingContext(ctx)
}

func requestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID := r.Header.Get("X-Request-ID")
		if requestID == "" {
			requestID = newRequestID()
		}
		ctx := context.WithValue(r.Context(), requestIDKey, requestID)
		w.Header().Set("X-Request-ID", requestID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func loggingMiddleware(next http.Handler, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		recorder := &statusRecorder{ResponseWriter: w}
		next.ServeHTTP(recorder, r)
		status := recorder.statusCode()
		logger.Info("http_request", "timestamp", time.Now().UTC().Format(time.RFC3339Nano), "request_id", requestID(r.Context()), "method", r.Method, "path", r.URL.Path, "status", status, "latency_ms", time.Since(started).Milliseconds(), "error_code", errorCodeForStatus(status))
	})
}

func errorCodeForStatus(status int) string {
	switch status {
	case http.StatusNotFound:
		return "NOT_FOUND"
	case http.StatusServiceUnavailable:
		return "DATABASE_UNAVAILABLE"
	case http.StatusInternalServerError:
		return "INTERNAL_ERROR"
	default:
		return ""
	}
}

func recoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recover() != nil {
				writeAppError(w, r, AppError{Status: http.StatusInternalServerError, Code: "INTERNAL_ERROR", Message: "服务暂时不可用"})
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func writeAppError(w http.ResponseWriter, r *http.Request, appErr AppError) {
	requestID := requestID(r.Context())
	if requestID == "" {
		requestID = newRequestID()
	}
	writeJSON(w, appErr.Status, map[string]any{"code": appErr.Code, "message": appErr.Message, "request_id": requestID, "details": appErr.Details})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func requestID(ctx context.Context) string {
	value, _ := ctx.Value(requestIDKey).(string)
	return value
}

func newRequestID() string {
	var bytes [12]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "req_fallback"
	}
	return "req_" + hex.EncodeToString(bytes[:])
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	if r.status != 0 {
		return
	}
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func (r *statusRecorder) Write(body []byte) (int, error) {
	if r.status == 0 {
		r.WriteHeader(http.StatusOK)
	}
	return r.ResponseWriter.Write(body)
}

func (r *statusRecorder) statusCode() int {
	if r.status == 0 {
		return http.StatusOK
	}
	return r.status
}
