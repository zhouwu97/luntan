package httpserver

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func writeTestAppRelease(t *testing.T) *AppRelease {
	t.Helper()
	directory := t.TempDir()
	content := []byte("deterministic android package content")
	digest := sha256.Sum256(content)
	digestHex := hex.EncodeToString(digest[:])
	if err := os.WriteFile(filepath.Join(directory, "luntan-1.2.0.apk"), content, 0o644); err != nil {
		t.Fatal(err)
	}
	manifest := map[string]any{
		"version_name":                   "1.2.0",
		"version_code":                   12,
		"minimum_supported_version_code": 10,
		"title":                          "圣杯酱 1.2.0",
		"changelog":                      "修复下载链路并优化更新体验。",
		"apk_file":                       "luntan-1.2.0.apk",
		"sha256":                         digestHex,
		"published_at":                   "2026-08-30T00:00:00+08:00",
	}
	raw, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	manifestPath := filepath.Join(directory, "release.json")
	if err := os.WriteFile(manifestPath, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	release, err := LoadAppRelease(manifestPath, "https://download.example.com")
	if err != nil {
		t.Fatal(err)
	}
	return release
}

func newReleaseTestHandler(t *testing.T, release *AppRelease) http.Handler {
	t.Helper()
	handler, err := NewHandlerWithAPIOptions(nil, slog.New(slog.NewTextHandler(io.Discard, nil)), nil, Options{AppRelease: release})
	if err != nil {
		t.Fatal(err)
	}
	return handler
}

func TestAppReleaseLatestAndUpdateShareMetadata(t *testing.T) {
	handler := newReleaseTestHandler(t, writeTestAppRelease(t))

	latestRequest := httptest.NewRequest(http.MethodGet, "/api/v1/app/releases/latest", nil)
	latestResponse := httptest.NewRecorder()
	handler.ServeHTTP(latestResponse, latestRequest)
	if latestResponse.Code != http.StatusOK {
		t.Fatalf("latest status=%d body=%s", latestResponse.Code, latestResponse.Body.String())
	}
	var latest map[string]any
	if err := json.Unmarshal(latestResponse.Body.Bytes(), &latest); err != nil {
		t.Fatal(err)
	}

	updateRequest := httptest.NewRequest(http.MethodGet, "/api/v1/app/update?platform=android&channel=stable&version_name=1.0.0&version_code=9", nil)
	updateResponse := httptest.NewRecorder()
	handler.ServeHTTP(updateResponse, updateRequest)
	if updateResponse.Code != http.StatusOK {
		t.Fatalf("update status=%d body=%s", updateResponse.Code, updateResponse.Body.String())
	}
	var update map[string]any
	if err := json.Unmarshal(updateResponse.Body.Bytes(), &update); err != nil {
		t.Fatal(err)
	}
	if update["update_type"] != "required" || update["update_available"] != true {
		t.Fatalf("unexpected update policy: %#v", update)
	}
	if !strings.HasSuffix(update["download_url"].(string), "/api/v1/app/releases/12/download") {
		t.Fatalf("download URL must be version-specific: %v", update["download_url"])
	}
	for _, key := range []string{"latest_version_name", "latest_version_code", "file_size", "sha256", "download_url"} {
		if latest[key] != update[key] {
			t.Fatalf("metadata %s drifted: latest=%v update=%v", key, latest[key], update[key])
		}
	}
}

func TestAppReleaseUpdateCurrentVersionReturnsNone(t *testing.T) {
	handler := newReleaseTestHandler(t, writeTestAppRelease(t))
	request := httptest.NewRequest(http.MethodGet, "/api/v1/app/update?platform=android&channel=stable&version_name=1.2.0&version_code=12", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK || !strings.Contains(response.Body.String(), `"update_type":"none"`) || !strings.Contains(response.Body.String(), `"download_url":""`) {
		t.Fatalf("unexpected response: status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestAppReleaseDownloadSupportsHeadAndRange(t *testing.T) {
	release := writeTestAppRelease(t)
	handler := newReleaseTestHandler(t, release)

	headRequest := httptest.NewRequest(http.MethodHead, release.downloadPath(), nil)
	headResponse := httptest.NewRecorder()
	handler.ServeHTTP(headResponse, headRequest)
	if headResponse.Code != http.StatusOK || headResponse.Body.Len() != 0 || headResponse.Header().Get("Content-Disposition") == "" {
		t.Fatalf("unexpected HEAD response: status=%d headers=%v body=%q", headResponse.Code, headResponse.Header(), headResponse.Body.String())
	}

	rangeRequest := httptest.NewRequest(http.MethodGet, release.downloadPath(), nil)
	rangeRequest.Header.Set("Range", "bytes=0-7")
	rangeResponse := httptest.NewRecorder()
	handler.ServeHTTP(rangeResponse, rangeRequest)
	if rangeResponse.Code != http.StatusPartialContent || rangeResponse.Body.Len() != 8 || rangeResponse.Header().Get("Content-Range") == "" {
		t.Fatalf("unexpected range response: status=%d headers=%v len=%d", rangeResponse.Code, rangeResponse.Header(), rangeResponse.Body.Len())
	}
}

func TestLoadAppReleaseRejectsTraversalAndDigestMismatch(t *testing.T) {
	directory := t.TempDir()
	outside := filepath.Join(directory, "outside.apk")
	if err := os.WriteFile(outside, []byte("apk"), 0o644); err != nil {
		t.Fatal(err)
	}
	manifestDirectory := filepath.Join(directory, "manifest")
	if err := os.Mkdir(manifestDirectory, 0o755); err != nil {
		t.Fatal(err)
	}
	manifest := `{"version_name":"1.0.0","version_code":1,"minimum_supported_version_code":1,"title":"title","changelog":"changes","apk_file":"../outside.apk","sha256":"` + strings.Repeat("0", 64) + `","published_at":"` + time.Now().UTC().Format(time.RFC3339) + `"}`
	manifestPath := filepath.Join(manifestDirectory, "release.json")
	if err := os.WriteFile(manifestPath, []byte(manifest), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadAppRelease(manifestPath, ""); err == nil || !strings.Contains(err.Error(), "inside") {
		t.Fatalf("expected traversal error, got %v", err)
	}
}

func TestAppReleaseUnavailableIsExplicit(t *testing.T) {
	handler := newReleaseTestHandler(t, nil)
	request := httptest.NewRequest(http.MethodGet, "/api/v1/app/releases/latest", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusServiceUnavailable || !strings.Contains(response.Body.String(), "APP_RELEASE_UNAVAILABLE") {
		t.Fatalf("unexpected unavailable response: status=%d body=%s", response.Code, response.Body.String())
	}
}
