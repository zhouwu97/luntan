package httpserver

import (
	"net/http/httptest"
	"testing"
	"time"
)

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
