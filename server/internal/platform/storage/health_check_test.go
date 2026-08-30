package storage

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func TestHTTPMediaStorageHealthCheck(t *testing.T) {
	cases := []struct {
		name    string
		status  int
		wantErr bool
	}{
		{"probe key missing", http.StatusNotFound, false},
		{"storage reachable", http.StatusOK, false},
		{"signature rejected", http.StatusForbidden, true},
		{"storage erroring", http.StatusInternalServerError, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(tc.status)
			}))
			defer server.Close()
			backend := NewHTTPMediaStorage(server.URL, "", "health-secret", "")
			err := backend.HealthCheck(context.Background())
			if tc.wantErr && err == nil {
				t.Fatalf("expected error for status %d", tc.status)
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error for status %d: %v", tc.status, err)
			}
		})
	}
}

func TestHTTPMediaStorageHealthCheckNetworkFailure(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	server.Close()
	backend := NewHTTPMediaStorage(server.URL, "", "health-secret", "")
	if err := backend.HealthCheck(context.Background()); err == nil {
		t.Fatal("expected error when storage service is unreachable")
	}
}

func TestHTTPMediaStorageHealthCheckUsesInternalURL(t *testing.T) {
	var gotPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()
	backend := NewHTTPMediaStorage("", server.URL, "", "")
	if err := backend.HealthCheck(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if gotPath != "/.readiness-probe" {
		t.Fatalf("probe path = %q", gotPath)
	}
}

func TestLocalMediaStorageHealthCheck(t *testing.T) {
	healthy := NewLocalMediaStorage(t.TempDir(), "secret")
	if err := healthy.HealthCheck(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	missing := NewLocalMediaStorage(filepath.Join(t.TempDir(), "not-created"), "secret")
	if err := missing.HealthCheck(context.Background()); !errors.Is(err, ErrStorageUnavailable) {
		t.Fatalf("expected ErrStorageUnavailable, got: %v", err)
	}
}

func TestUnavailableMediaStorageHealthCheck(t *testing.T) {
	if err := (UnavailableMediaStorage{}).HealthCheck(context.Background()); !errors.Is(err, ErrStorageUnavailable) {
		t.Fatalf("expected ErrStorageUnavailable, got: %v", err)
	}
}
