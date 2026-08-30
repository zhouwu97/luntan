package httpserver

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
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
	ExpiresAt time.Time
	Count     int
}

// RateLimitStore 是限流状态的持久化接缝；生产环境使用 Redis，
// 开发和单元测试可使用带回收机制的进程内实现。
type RateLimitStore interface {
	Allow(ctx context.Context, key string, limit int, window time.Duration, now time.Time) (bool, error)
}

type memoryRateLimitStore struct {
	mu           sync.Mutex
	buckets      map[string]rateLimitBucket
	operations   uint64
	cleanupEvery uint64
	maxBuckets   int
}

func newMemoryRateLimitStore() *memoryRateLimitStore {
	return &memoryRateLimitStore{
		buckets:      make(map[string]rateLimitBucket),
		cleanupEvery: 256,
		maxBuckets:   100_000,
	}
}

// NewMemoryRateLimitStore 返回适用于开发或单实例部署的限流存储。
func NewMemoryRateLimitStore() RateLimitStore { return newMemoryRateLimitStore() }

func (s *memoryRateLimitStore) Allow(_ context.Context, key string, limit int, window time.Duration, now time.Time) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.operations++
	if s.cleanupEvery > 0 && s.operations%s.cleanupEvery == 0 {
		s.purgeExpired(now)
	}
	bucket, exists := s.buckets[key]
	if !exists || !now.Before(bucket.ExpiresAt) {
		if !exists && len(s.buckets) >= s.maxBuckets {
			s.purgeExpired(now)
			if len(s.buckets) >= s.maxBuckets {
				// 基数异常时失败关闭，避免攻击者通过随机来源地址耗尽内存。
				return false, nil
			}
		}
		s.buckets[key] = rateLimitBucket{ExpiresAt: now.Add(window), Count: 1}
		return true, nil
	}
	if bucket.Count >= limit {
		return false, nil
	}
	bucket.Count++
	s.buckets[key] = bucket
	return true, nil
}

func (s *memoryRateLimitStore) purgeExpired(now time.Time) {
	for key, bucket := range s.buckets {
		if !now.Before(bucket.ExpiresAt) {
			delete(s.buckets, key)
		}
	}
}

type rateLimiter struct {
	store RateLimitStore
	rules map[string]rateLimitRule
}

func newRateLimiter(stores ...RateLimitStore) *rateLimiter {
	store := RateLimitStore(newMemoryRateLimitStore())
	if len(stores) > 0 && stores[0] != nil {
		store = stores[0]
	}
	return &rateLimiter{
		store: store,
		rules: map[string]rateLimitRule{
			"register":     {Limit: 5, Window: time.Minute},
			"login":        {Limit: 10, Window: time.Minute},
			"email_code":   {Limit: 5, Window: time.Minute},
			"email_verify": {Limit: 10, Window: time.Minute},
			// 验证码校验同时按 IP 和邮箱限流；邮箱维度使用单独更严格的规则。
			"email_verify_email": {Limit: 5, Window: time.Minute},
			"guest":              {Limit: 20, Window: time.Hour},
			"refresh":            {Limit: 20, Window: time.Minute},
			"publish":            {Limit: 20, Window: time.Minute},
			"comment":            {Limit: 30, Window: time.Minute},
			"like":               {Limit: 60, Window: time.Minute},
			"follow":             {Limit: 30, Window: time.Minute},
			"report":             {Limit: 10, Window: time.Minute},
			"upload_token":       {Limit: 30, Window: time.Minute},
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
		rule, exists := l.rules[route]
		if !exists {
			next.ServeHTTP(w, r)
			return
		}
		now := time.Now()
		key := "luntan:rate_limit:" + route + ":ip:" + ClientIP(r)
		allowed, err := l.store.Allow(r.Context(), key, rule.Limit, rule.Window, now)
		if err != nil {
			WriteAppError(w, r, AppError{Status: http.StatusServiceUnavailable, Code: "RATE_LIMIT_UNAVAILABLE", Message: "服务暂时不可用"})
			return
		}
		if !allowed {
			WriteAppError(w, r, AppError{Status: http.StatusTooManyRequests, Code: "RATE_LIMITED", Message: "请求过于频繁，请稍后再试"})
			return
		}
		if route == "email_verify" {
			if email := emailFromRequest(r); email != "" {
				emailRule := l.rules["email_verify_email"]
				emailKey := "luntan:rate_limit:email_verify:email:" + hashRateLimitDimension(email)
				allowed, err = l.store.Allow(r.Context(), emailKey, emailRule.Limit, emailRule.Window, now)
				if err != nil {
					WriteAppError(w, r, AppError{Status: http.StatusServiceUnavailable, Code: "RATE_LIMIT_UNAVAILABLE", Message: "服务暂时不可用"})
					return
				}
				if !allowed {
					WriteAppError(w, r, AppError{Status: http.StatusTooManyRequests, Code: "RATE_LIMITED", Message: "请求过于频繁，请稍后再试"})
					return
				}
			}
		}
		next.ServeHTTP(w, r)
	})
}

func classifyRateLimitRoute(r *http.Request) string {
	path := strings.TrimSuffix(r.URL.Path, "/")
	switch {
	case r.Method == http.MethodPost && path == "/api/v1/auth/register":
		return "register"
	case r.Method == http.MethodPost && (path == "/api/v1/auth/login" || path == "/api/v1/auth/login/password"):
		return "login"
	case r.Method == http.MethodPost && (path == "/api/v1/auth/email/request" || path == "/api/v1/auth/code/request"):
		return "email_code"
	case r.Method == http.MethodPost && (path == "/api/v1/auth/email/verify" || path == "/api/v1/auth/login/code"):
		return "email_verify"
	case r.Method == http.MethodPost && path == "/api/v1/auth/guest":
		return "guest"
	case r.Method == http.MethodPost && path == "/api/v1/auth/refresh":
		return "refresh"
	case path == "/api/v1/posts" && r.Method == http.MethodPost:
		return "publish"
	case strings.HasSuffix(path, "/comments") && r.Method == http.MethodPost:
		return "comment"
	case strings.HasSuffix(path, "/replies") && r.Method == http.MethodPost:
		return "comment"
	case (strings.HasSuffix(path, "/like") || strings.HasSuffix(path, "/bookmark")) && (r.Method == http.MethodPut || r.Method == http.MethodDelete):
		return "like"
	case (strings.HasSuffix(path, "/follow") || strings.HasSuffix(path, "/membership")) && (r.Method == http.MethodPut || r.Method == http.MethodDelete):
		return "follow"
	case path == "/api/v1/reports" && r.Method == http.MethodPost:
		return "report"
	case path == "/api/v1/media/upload-token" && r.Method == http.MethodPost:
		return "upload_token"
	default:
		return ""
	}
}

// emailFromRequest 在读取后恢复请求体，确保限流中间件不会改变下游 handler
// 的 JSON 输入。解析失败时仍保留 IP 维度限流，避免攻击者用畸形 body 绕过。
func emailFromRequest(r *http.Request) string {
	if r == nil || r.Body == nil {
		return ""
	}
	originalBody := r.Body
	payload, err := io.ReadAll(io.LimitReader(originalBody, (1<<20)+1))
	_ = originalBody.Close()
	r.Body = io.NopCloser(bytes.NewReader(payload))
	if err != nil || len(payload) > 1<<20 {
		return ""
	}
	var input struct {
		Email string `json:"email"`
	}
	if err := json.Unmarshal(payload, &input); err != nil {
		return ""
	}
	email := strings.ToLower(strings.TrimSpace(input.Email))
	if len(email) < 5 || len(email) > 320 {
		return ""
	}
	return email
}

func hashRateLimitDimension(value string) string {
	hash := sha256.Sum256([]byte(value))
	return hex.EncodeToString(hash[:])
}
