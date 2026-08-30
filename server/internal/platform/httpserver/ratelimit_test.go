package httpserver

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestClassifyRateLimitRouteCoversAuthenticationAliases(t *testing.T) {
	cases := []struct {
		name   string
		method string
		path   string
		want   string
	}{
		{name: "canonical password login", method: http.MethodPost, path: "/api/v1/auth/login", want: "login"},
		{name: "legacy password login", method: http.MethodPost, path: "/api/v1/auth/login/password", want: "login"},
		{name: "canonical code request", method: http.MethodPost, path: "/api/v1/auth/email/request", want: "email_code"},
		{name: "legacy code request", method: http.MethodPost, path: "/api/v1/auth/code/request", want: "email_code"},
		{name: "canonical code verify", method: http.MethodPost, path: "/api/v1/auth/email/verify", want: "email_verify"},
		{name: "legacy code verify", method: http.MethodPost, path: "/api/v1/auth/login/code", want: "email_verify"},
		{name: "wrong method is not auth attempt", method: http.MethodGet, path: "/api/v1/auth/login/password", want: ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(tc.method, tc.path, nil)
			if got := classifyRateLimitRoute(req); got != tc.want {
				t.Fatalf("route class = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestEmailVerifyRateLimitUsesIPAndEmailAndRestoresBody(t *testing.T) {
	store := newMemoryRateLimitStore()
	var seenBody string
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read restored body: %v", err)
		}
		seenBody = string(body)
		w.WriteHeader(http.StatusNoContent)
	})
	handler := newRateLimiter(store).middleware(next)
	for index := 0; index < 5; index++ {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login/code", strings.NewReader(`{"email":"same@example.com","code":"000000"}`))
		req.RemoteAddr = "198.51.100.30:4321"
		res := httptest.NewRecorder()
		handler.ServeHTTP(res, req)
		if res.Code != http.StatusNoContent {
			t.Fatalf("request %d status = %d, want 204", index+1, res.Code)
		}
	}
	blocked := httptest.NewRequest(http.MethodPost, "/api/v1/auth/email/verify", strings.NewReader(`{"email":"same@example.com","code":"000000"}`))
	blocked.RemoteAddr = "198.51.100.30:4321"
	blockedRes := httptest.NewRecorder()
	handler.ServeHTTP(blockedRes, blocked)
	if blockedRes.Code != http.StatusTooManyRequests {
		t.Fatalf("sixth request status = %d, want 429", blockedRes.Code)
	}
	if seenBody != `{"email":"same@example.com","code":"000000"}` {
		t.Fatalf("downstream body = %q, want original JSON", seenBody)
	}
}

func TestClientIPResolverIgnoresForwardedHeadersFromUntrustedPeer(t *testing.T) {
	resolver, err := newClientIPResolver([]string{"10.0.0.0/8"})
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("GET", "/", nil)
	req.RemoteAddr = "198.51.100.20:4321"
	req.Header.Set("X-Forwarded-For", "203.0.113.99")
	req.Header.Set("X-Real-IP", "203.0.113.98")

	if got := resolver.Resolve(req); got != "198.51.100.20" {
		t.Fatalf("client IP = %q, want direct peer", got)
	}
}

func TestClientIPResolverWalksTrustedProxyChainFromRight(t *testing.T) {
	resolver, err := newClientIPResolver([]string{"10.0.0.0/8"})
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("GET", "/", nil)
	req.RemoteAddr = "10.0.0.3:4321"
	req.Header.Set("X-Forwarded-For", "198.51.100.20, 10.0.0.2")

	if got := resolver.Resolve(req); got != "198.51.100.20" {
		t.Fatalf("client IP = %q, want first untrusted hop", got)
	}
}

func TestClientIPResolverRejectsInvalidTrustedCIDR(t *testing.T) {
	if _, err := newClientIPResolver([]string{"not-a-cidr"}); err == nil {
		t.Fatal("invalid trusted proxy CIDR should fail startup")
	}
	if _, err := newClientIPResolver([]string{"0.0.0.0/0"}); err == nil {
		t.Fatal("catch-all trusted proxy CIDR should fail startup")
	}
}

func TestMemoryRateLimitStorePurgesExpiredBuckets(t *testing.T) {
	store := newMemoryRateLimitStore()
	store.cleanupEvery = 1
	now := time.Date(2026, 8, 24, 10, 0, 0, 0, time.UTC)
	if allowed, err := store.Allow(t.Context(), "expired", 1, time.Minute, now); err != nil || !allowed {
		t.Fatalf("first allow: allowed=%v err=%v", allowed, err)
	}
	if allowed, err := store.Allow(t.Context(), "fresh", 1, time.Minute, now.Add(2*time.Minute)); err != nil || !allowed {
		t.Fatalf("second allow: allowed=%v err=%v", allowed, err)
	}
	if _, exists := store.buckets["expired"]; exists {
		t.Fatal("expired bucket was not purged")
	}
}
