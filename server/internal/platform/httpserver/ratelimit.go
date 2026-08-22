package httpserver

import (
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

func rateLimitEnabled() bool {
	return strings.EqualFold(strings.TrimSpace(os.Getenv("RATE_LIMIT_ENABLED")), "true")
}

type rateLimitRule struct {
	Limit  int
	Window time.Duration
}

type rateLimitBucket struct {
	Started time.Time
	Count   int
}

type rateLimiter struct {
	mu      sync.Mutex
	buckets map[string]rateLimitBucket
	rules   map[string]rateLimitRule
}

func newRateLimiter() *rateLimiter {
	return &rateLimiter{
		buckets: make(map[string]rateLimitBucket),
		rules: map[string]rateLimitRule{
			"register":     {Limit: 5, Window: time.Minute},
			"login":        {Limit: 10, Window: time.Minute},
			"refresh":      {Limit: 20, Window: time.Minute},
			"publish":      {Limit: 20, Window: time.Minute},
			"comment":      {Limit: 30, Window: time.Minute},
			"like":         {Limit: 60, Window: time.Minute},
			"follow":       {Limit: 30, Window: time.Minute},
			"report":       {Limit: 10, Window: time.Minute},
			"upload_token": {Limit: 30, Window: time.Minute},
		},
	}
}

func (l *rateLimiter) middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		route := classifyRateLimitRoute(r)
		if route == "" {
			next.ServeHTTP(w, r)
			return
		}
		rule := l.rules[route]
		key := route + ":" + clientAddress(r)
		if !l.allow(key, rule, time.Now()) {
			WriteAppError(w, r, AppError{Status: http.StatusTooManyRequests, Code: "RATE_LIMITED", Message: "请求过于频繁，请稍后再试"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (l *rateLimiter) allow(key string, rule rateLimitRule, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	bucket := l.buckets[key]
	if bucket.Started.IsZero() || now.Sub(bucket.Started) >= rule.Window {
		l.buckets[key] = rateLimitBucket{Started: now, Count: 1}
		return true
	}
	if bucket.Count >= rule.Limit {
		return false
	}
	bucket.Count++
	l.buckets[key] = bucket
	return true
}

func classifyRateLimitRoute(r *http.Request) string {
	path := strings.TrimSuffix(r.URL.Path, "/")
	switch {
	case path == "/api/v1/auth/register":
		return "register"
	case path == "/api/v1/auth/login":
		return "login"
	case path == "/api/v1/auth/refresh":
		return "refresh"
	case path == "/api/v1/posts" && r.Method == http.MethodPost:
		return "publish"
	case strings.HasSuffix(path, "/comments") && r.Method == http.MethodPost:
		return "comment"
	case strings.HasSuffix(path, "/replies") && r.Method == http.MethodPost:
		return "comment"
	case (strings.HasSuffix(path, "/like") || strings.HasSuffix(path, "/bookmark")) && (r.Method == http.MethodPut || r.Method == http.MethodDelete):
		return "like"
	case strings.HasSuffix(path, "/follow") || strings.HasSuffix(path, "/membership"):
		return "follow"
	case path == "/api/v1/reports" && r.Method == http.MethodPost:
		return "report"
	case path == "/api/v1/media/upload-token" && r.Method == http.MethodPost:
		return "upload_token"
	default:
		return ""
	}
}

func clientAddress(r *http.Request) string {
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	if r.RemoteAddr == "" {
		return "unknown"
	}
	return r.RemoteAddr
}
