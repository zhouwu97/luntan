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
	"os"
	"strings"
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

type Options struct {
	RateLimitEnabled  bool
	RateLimitStore    RateLimitStore
	TrustedProxyCIDRs []string
	// ReadinessCheck 用于检查 API 依赖的非数据库资源，例如对象存储。
	// 留空表示只检查数据库，兼容没有业务 API 的基础 HTTP server。
	ReadinessCheck func(context.Context) error
}

// BuildVersion 和 BuildCommit 由构建命令通过 -ldflags 注入，开发环境使用默认值。
var (
	BuildVersion = "dev"
	BuildCommit  = "unknown"
)

func (e AppError) Error() string { return e.Code }

func NewHandler(db *sql.DB, logger *slog.Logger) http.Handler {
	return NewHandlerWithAPI(db, logger, nil)
}

func NewHandlerWithAPI(db *sql.DB, logger *slog.Logger, apiHandler http.Handler) http.Handler {
	handler, err := NewHandlerWithAPIOptions(db, logger, apiHandler, Options{
		RateLimitEnabled:  rateLimitEnabled(),
		TrustedProxyCIDRs: splitCommaSeparated(os.Getenv("TRUSTED_PROXY_CIDRS")),
	})
	if err != nil {
		panic(err)
	}
	return handler
}

func NewHandlerWithAPIOptions(db *sql.DB, logger *slog.Logger, apiHandler http.Handler, options Options) (http.Handler, error) {
	if logger == nil {
		logger = slog.Default()
	}
	resolver, err := newClientIPResolver(options.TrustedProxyCIDRs)
	if err != nil {
		return nil, err
	}
	router := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/health":
			WriteJSON(w, http.StatusOK, buildInfoPayload("ok"))
		case r.Method == http.MethodGet && r.URL.Path == "/version":
			WriteJSON(w, http.StatusOK, buildInfoPayload("ok"))
		case r.Method == http.MethodGet && r.URL.Path == "/metrics":
			w.Header().Set("Content-Type", "text/plain; version=0.0.4")
			metrics.write(w)
		case r.Method == http.MethodGet && r.URL.Path == "/ready":
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			defer cancel()
			if err := pingDatabase(ctx, db); err != nil {
				WriteAppError(w, r, AppError{Status: http.StatusServiceUnavailable, Code: "DATABASE_UNAVAILABLE", Message: "服务暂时不可用"})
				return
			}
			if options.ReadinessCheck != nil {
				if err := options.ReadinessCheck(ctx); err != nil {
					WriteAppError(w, r, AppError{Status: http.StatusServiceUnavailable, Code: "DEPENDENCY_UNAVAILABLE", Message: "服务依赖暂时不可用"})
					return
				}
			}
			WriteJSON(w, http.StatusOK, map[string]string{"status": "ready"})
		case apiHandler != nil && len(r.URL.Path) >= len("/api/") && r.URL.Path[:len("/api/")] == "/api/":
			apiHandler.ServeHTTP(w, r)
		default:
			WriteAppError(w, r, AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "请求资源不存在"})
		}
	})
	var root http.Handler = gzipMiddleware(router)
	if options.RateLimitEnabled {
		root = newRateLimiter(options.RateLimitStore).middleware(root)
	}
	root = clientIPMiddleware(root, resolver)
	root = corsMiddleware(root)
	return requestIDMiddleware(loggingMiddleware(recoveryMiddleware(root), logger)), nil
}

// corsMiddleware 让公开 Feed、榜单和媒体元数据可以被 Flutter Web 跨域读取。
// 互动请求仍由 API 自身的认证与权限逻辑保护；这里仅处理浏览器预检和响应头。
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type, Authorization, Idempotency-Key, X-Request-ID")
		w.Header().Set("Access-Control-Expose-Headers", "X-Request-ID")
		w.Header().Set("Vary", "Origin")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func buildInfoPayload(status string) map[string]string {
	return map[string]string{
		"status":  status,
		"version": BuildVersion,
		"commit":  BuildCommit,
	}
}

func splitCommaSeparated(value string) []string {
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
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
		latency := time.Since(started)
		metrics.observe(status, latency)
		metrics.observeBusiness(r.URL.Path, status)
		logger.Info("http_request", "timestamp", time.Now().UTC().Format(time.RFC3339Nano), "request_id", requestID(r.Context()), "method", r.Method, "path", r.URL.Path, "status", status, "latency_ms", latency.Milliseconds(), "error_code", errorCodeForStatus(status))
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
				WriteAppError(w, r, AppError{Status: http.StatusInternalServerError, Code: "INTERNAL_ERROR", Message: "服务暂时不可用"})
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func WriteAppError(w http.ResponseWriter, r *http.Request, appErr AppError) {
	requestID := requestID(r.Context())
	if requestID == "" {
		requestID = newRequestID()
	}
	WriteJSON(w, appErr.Status, map[string]any{"code": appErr.Code, "message": appErr.Message, "request_id": requestID, "details": appErr.Details})
}

func WriteJSON(w http.ResponseWriter, status int, payload any) {
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
