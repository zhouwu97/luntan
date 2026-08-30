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
	"strconv"
	"strings"
	"testing"
	"time"
)

func writeTestAppRelease(t *testing.T) *AppRelease {
	return writeTestAppReleaseWithBases(t, "https://download.example.com", "")
}

func writeTestAppReleaseWithBases(t *testing.T, publicBaseURL, downloadBaseURL string) *AppRelease {
	t.Helper()
	directory := t.TempDir()
	content := []byte("deterministic android package content")
	digest := sha256.Sum256(content)
	digestHex := hex.EncodeToString(digest[:])
	versionDirectory := filepath.Join(directory, "releases", "12")
	if err := os.MkdirAll(versionDirectory, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(versionDirectory, "luntan-1.2.0.apk"), content, 0o644); err != nil {
		t.Fatal(err)
	}
	manifest := map[string]any{
		"version_name":                   "1.2.0",
		"version_code":                   12,
		"minimum_supported_version_code": 10,
		"title":                          "圣杯酱 1.2.0",
		"changelog":                      "修复下载链路并优化更新体验。",
		"apk_file":                       "releases/12/luntan-1.2.0.apk",
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
	release, err := LoadAppRelease(manifestPath, publicBaseURL, downloadBaseURL)
	if err != nil {
		t.Fatal(err)
	}
	return release
}

func TestAppReleaseUsesStaticDownloadBaseURL(t *testing.T) {
	release := writeTestAppReleaseWithBases(t, "https://download.example.com", "https://dl.example.com")
	if got, want := release.downloadURL(), "https://dl.example.com/releases/12/luntan-1.2.0.apk"; got != want {
		t.Fatalf("static download URL=%q, want %q", got, want)
	}
	payload := release.releasePayload()
	if payload["download_url"] != "https://dl.example.com/releases/12/luntan-1.2.0.apk" {
		t.Fatalf("payload download_url=%v", payload["download_url"])
	}
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
	if headResponse.Header().Get("Cache-Control") != "public, max-age=2592000, immutable" {
		t.Fatalf("APK cache policy must be long-lived: %q", headResponse.Header().Get("Cache-Control"))
	}

	rangeRequest := httptest.NewRequest(http.MethodGet, release.downloadPath(), nil)
	rangeRequest.Header.Set("Range", "bytes=0-7")
	rangeResponse := httptest.NewRecorder()
	handler.ServeHTTP(rangeResponse, rangeRequest)
	if rangeResponse.Code != http.StatusPartialContent || rangeResponse.Body.Len() != 8 || rangeResponse.Header().Get("Content-Range") == "" {
		t.Fatalf("unexpected range response: status=%d headers=%v len=%d", rangeResponse.Code, rangeResponse.Header(), rangeResponse.Body.Len())
	}

	invalidRangeRequest := httptest.NewRequest(http.MethodGet, release.downloadPath(), nil)
	invalidRangeRequest.Header.Set("Range", "bytes=999-")
	invalidRangeResponse := httptest.NewRecorder()
	handler.ServeHTTP(invalidRangeResponse, invalidRangeRequest)
	if invalidRangeResponse.Code != http.StatusRequestedRangeNotSatisfiable ||
		invalidRangeResponse.Header().Get("Content-Range") != "bytes */"+strconv.FormatInt(release.FileSize, 10) {
		t.Fatalf("unexpected invalid range response: status=%d headers=%v", invalidRangeResponse.Code, invalidRangeResponse.Header())
	}
}

func TestAppReleaseHTTPIntegrationSupportsPolicyAndRange(t *testing.T) {
	release := writeTestAppRelease(t)
	server := httptest.NewServer(newReleaseTestHandler(t, release))
	defer server.Close()

	policyResponse, err := server.Client().Get(server.URL + "/api/v1/app/update?platform=android&channel=stable&version_name=1.0.0&version_code=9")
	if err != nil {
		t.Fatal(err)
	}
	defer policyResponse.Body.Close()
	if policyResponse.StatusCode != http.StatusOK {
		t.Fatalf("policy status=%d", policyResponse.StatusCode)
	}
	var policy map[string]any
	if err := json.NewDecoder(policyResponse.Body).Decode(&policy); err != nil {
		t.Fatal(err)
	}
	if policy["update_type"] != "required" || policy["update_available"] != true {
		t.Fatalf("unexpected policy over real HTTP: %#v", policy)
	}

	optionalResponse, err := server.Client().Get(server.URL + "/api/v1/app/update?platform=android&channel=stable&version_name=1.1.0&version_code=11")
	if err != nil {
		t.Fatal(err)
	}
	defer optionalResponse.Body.Close()
	var optionalPolicy map[string]any
	if err := json.NewDecoder(optionalResponse.Body).Decode(&optionalPolicy); err != nil {
		t.Fatal(err)
	}
	if optionalPolicy["update_type"] != "optional" || optionalPolicy["update_available"] != true {
		t.Fatalf("unexpected optional policy over real HTTP: %#v", optionalPolicy)
	}

	rangeRequest, err := http.NewRequest(http.MethodGet, server.URL+release.downloadPath(), nil)
	if err != nil {
		t.Fatal(err)
	}
	rangeRequest.Header.Set("Range", "bytes=0-7")
	rangeResponse, err := server.Client().Do(rangeRequest)
	if err != nil {
		t.Fatal(err)
	}
	defer rangeResponse.Body.Close()
	body, err := io.ReadAll(rangeResponse.Body)
	if err != nil {
		t.Fatal(err)
	}
	if rangeResponse.StatusCode != http.StatusPartialContent || len(body) != 8 ||
		rangeResponse.Header.Get("ETag") != `"`+release.SHA256+`"` ||
		rangeResponse.Header.Get("Content-Length") != "8" {
		t.Fatalf("unexpected real HTTP range response: status=%d headers=%v len=%d", rangeResponse.StatusCode, rangeResponse.Header, len(body))
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
	if _, err := LoadAppRelease(manifestPath, "", ""); err == nil || !strings.Contains(err.Error(), "inside") {
		t.Fatalf("expected traversal error, got %v", err)
	}
}

func TestLoadAppReleaseRejectsDigestMismatchAtStartup(t *testing.T) {
	directory := t.TempDir()
	versionDirectory := filepath.Join(directory, "releases", "12")
	if err := os.MkdirAll(versionDirectory, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(versionDirectory, "app.apk"), []byte("actual"), 0o644); err != nil {
		t.Fatal(err)
	}
	manifest := `{"version_name":"1.2.0","version_code":12,"minimum_supported_version_code":10,"title":"title","changelog":"changes","apk_file":"releases/12/app.apk","sha256":"` + strings.Repeat("0", 64) + `","published_at":"2026-08-30T00:00:00Z"}`
	manifestPath := filepath.Join(directory, "release.json")
	if err := os.WriteFile(manifestPath, []byte(manifest), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadAppRelease(manifestPath, "", ""); err == nil || !strings.Contains(err.Error(), "sha256 mismatch") {
		t.Fatalf("expected digest mismatch, got %v", err)
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

func TestAppReleaseDownloadRejectsInPlaceOverwrite(t *testing.T) {
	release := writeTestAppRelease(t)
	handler := newReleaseTestHandler(t, release)

	// 同大小、不同内容的原地覆盖：SHA/ETag 仍是启动时算的旧值，此时继续下发
	// 就会出现“接口 SHA=旧包、实际下载=新包”，必须拒绝服务。
	overwritten := strings.Repeat("x", int(release.FileSize))
	if err := os.WriteFile(release.FilePath, []byte(overwritten), 0o644); err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodGet, release.downloadPath(), nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusServiceUnavailable || !strings.Contains(response.Body.String(), "APP_RELEASE_CHANGED") {
		t.Fatalf("expected APP_RELEASE_CHANGED after overwrite, got status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestLoadAppReleaseEnforcesImmutableApkPath(t *testing.T) {
	cases := []string{"app.apk", "luntan-1.0.0.apk", "packages/12/app.apk", "releases/13/app.apk", "releases/12/sub/app.apk"}
	for _, apkFile := range cases {
		t.Run(apkFile, func(t *testing.T) {
			directory := t.TempDir()
			manifest := `{"version_name":"1.0.0","version_code":12,"minimum_supported_version_code":10,"title":"t","changelog":"c","apk_file":"` + apkFile + `","sha256":"` + strings.Repeat("0", 64) + `","published_at":"2026-08-30T00:00:00+08:00"}`
			manifestPath := filepath.Join(directory, "release.json")
			if err := os.WriteFile(manifestPath, []byte(manifest), 0o644); err != nil {
				t.Fatal(err)
			}
			_, err := LoadAppRelease(manifestPath, "", "")
			if err == nil || !strings.Contains(err.Error(), "immutable path") {
				t.Fatalf("expected immutable path error for %q, got %v", apkFile, err)
			}
		})
	}
}
