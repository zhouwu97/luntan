package httpserver

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const appReleaseDownloadPrefix = "/api/v1/app/releases/"

// AppRelease 是经发布清单与磁盘文件双重校验后的只读发布快照。
// 客户端更新检查和网站下载接口必须共享这一份数据，避免版本号、大小和
// 安装包地址分别维护后发生漂移。
type AppRelease struct {
	VersionName                 string
	VersionCode                 int64
	MinimumSupportedVersionCode int64
	Title                       string
	Changelog                   string
	FileName                    string
	FilePath                    string
	FileSize                    int64
	// FileModTime 是启动校验摘要时的文件 mtime 快照。SHA256 只在启动算一次，
	// 下载时靠 size + mtime 双重比对确认磁盘文件未被原地替换。
	FileModTime   time.Time
	SHA256        string
	PublishedAt   time.Time
	PublicBaseURL string
}

type appReleaseManifest struct {
	VersionName                 string `json:"version_name"`
	VersionCode                 int64  `json:"version_code"`
	MinimumSupportedVersionCode int64  `json:"minimum_supported_version_code"`
	Title                       string `json:"title"`
	Changelog                   string `json:"changelog"`
	APKFile                     string `json:"apk_file"`
	SHA256                      string `json:"sha256"`
	PublishedAt                 string `json:"published_at"`
}

// LoadAppRelease 读取并校验发布清单。manifestPath 为空表示未启用应用分发；
// 一旦显式配置，任何格式、路径或摘要错误都会阻止服务以半可用状态启动。
func LoadAppRelease(manifestPath, publicBaseURL string) (*AppRelease, error) {
	manifestPath = strings.TrimSpace(manifestPath)
	if manifestPath == "" {
		return nil, nil
	}
	if err := validateReleasePublicBaseURL(publicBaseURL); err != nil {
		return nil, err
	}
	absoluteManifestPath, err := filepath.Abs(manifestPath)
	if err != nil {
		return nil, fmt.Errorf("resolve app release manifest: %w", err)
	}
	raw, err := os.ReadFile(absoluteManifestPath)
	if err != nil {
		return nil, fmt.Errorf("read app release manifest: %w", err)
	}
	var manifest appReleaseManifest
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&manifest); err != nil {
		return nil, fmt.Errorf("decode app release manifest: %w", err)
	}
	if err := validateAppReleaseManifest(manifest); err != nil {
		return nil, err
	}

	manifestDir := filepath.Dir(absoluteManifestPath)
	filePath := filepath.Join(manifestDir, filepath.FromSlash(manifest.APKFile))
	relative, err := filepath.Rel(manifestDir, filePath)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || filepath.IsAbs(relative) {
		return nil, errors.New("app release apk_file must stay inside the manifest directory")
	}
	if err := validateImmutableApkPath(manifest.APKFile, manifest.VersionCode); err != nil {
		return nil, err
	}
	info, err := os.Stat(filePath)
	if err != nil {
		return nil, fmt.Errorf("stat app release apk: %w", err)
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("app release apk_file must be a regular file")
	}
	file, err := os.Open(filePath)
	if err != nil {
		return nil, fmt.Errorf("open app release apk: %w", err)
	}
	hasher := sha256.New()
	_, copyErr := io.Copy(hasher, file)
	hashedInfo, statErr := file.Stat()
	closeErr := file.Close()
	if copyErr != nil {
		return nil, fmt.Errorf("hash app release apk: %w", copyErr)
	}
	if statErr != nil {
		return nil, fmt.Errorf("stat app release apk after hashing: %w", statErr)
	}
	if closeErr != nil {
		return nil, fmt.Errorf("close app release apk: %w", closeErr)
	}
	actualSHA256 := hex.EncodeToString(hasher.Sum(nil))
	if !strings.EqualFold(actualSHA256, manifest.SHA256) {
		return nil, fmt.Errorf("app release sha256 mismatch: manifest=%s actual=%s", manifest.SHA256, actualSHA256)
	}
	publishedAt, _ := time.Parse(time.RFC3339, manifest.PublishedAt)
	return &AppRelease{
		VersionName:                 strings.TrimSpace(manifest.VersionName),
		VersionCode:                 manifest.VersionCode,
		MinimumSupportedVersionCode: manifest.MinimumSupportedVersionCode,
		Title:                       strings.TrimSpace(manifest.Title),
		Changelog:                   strings.TrimSpace(manifest.Changelog),
		FileName:                    filepath.Base(filePath),
		FilePath:                    filePath,
		FileSize:                    hashedInfo.Size(),
		FileModTime:                 hashedInfo.ModTime(),
		SHA256:                      actualSHA256,
		PublishedAt:                 publishedAt.UTC(),
		PublicBaseURL:               strings.TrimRight(strings.TrimSpace(publicBaseURL), "/"),
	}, nil
}

// validateImmutableApkPath 强制发布包走按版本隔离的不可变路径
// （releases/<version_code>/xxx.apk）：发布新版本必须写新路径，从目录约定上
// 杜绝原地覆盖同一个 APK 文件。
func validateImmutableApkPath(apkFile string, versionCode int64) error {
	slash := filepath.ToSlash(filepath.Clean(filepath.FromSlash(strings.TrimSpace(apkFile))))
	expectedDir := "releases/" + strconv.FormatInt(versionCode, 10)
	if dir := path.Dir(slash); dir != expectedDir {
		return fmt.Errorf("app release apk_file must be %s/<file>.apk so each release keeps an immutable path", expectedDir)
	}
	return nil
}

func validateAppReleaseManifest(manifest appReleaseManifest) error {
	if strings.TrimSpace(manifest.VersionName) == "" || manifest.VersionCode <= 0 {
		return errors.New("app release version_name and positive version_code are required")
	}
	if manifest.MinimumSupportedVersionCode <= 0 || manifest.MinimumSupportedVersionCode > manifest.VersionCode {
		return errors.New("app release minimum_supported_version_code must be positive and not exceed version_code")
	}
	if strings.TrimSpace(manifest.Title) == "" || strings.TrimSpace(manifest.Changelog) == "" {
		return errors.New("app release title and changelog are required")
	}
	apkFile := filepath.Clean(filepath.FromSlash(strings.TrimSpace(manifest.APKFile)))
	if apkFile == "." || filepath.IsAbs(apkFile) || filepath.Ext(apkFile) != ".apk" {
		return errors.New("app release apk_file must be a relative .apk path")
	}
	shaValue := strings.ToLower(strings.TrimSpace(manifest.SHA256))
	if len(shaValue) != sha256.Size*2 {
		return errors.New("app release sha256 must contain 64 hexadecimal characters")
	}
	if _, err := hex.DecodeString(shaValue); err != nil {
		return errors.New("app release sha256 must contain 64 hexadecimal characters")
	}
	if _, err := time.Parse(time.RFC3339, strings.TrimSpace(manifest.PublishedAt)); err != nil {
		return errors.New("app release published_at must be RFC3339")
	}
	return nil
}

func (r *AppRelease) downloadURL() string {
	path := r.downloadPath()
	if r == nil || r.PublicBaseURL == "" {
		return path
	}
	return r.PublicBaseURL + path
}

// downloadPath 带版本号，允许 CDN 长期缓存但不会把旧 APK 返回给新版本。
func (r *AppRelease) downloadPath() string {
	if r == nil {
		return ""
	}
	return appReleaseDownloadPrefix + strconv.FormatInt(r.VersionCode, 10) + "/download"
}

func (r *AppRelease) matchesDownloadPath(path string) bool {
	return r != nil && path == r.downloadPath()
}

func (r *AppRelease) serveLatest(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "no-store")
	WriteJSON(w, http.StatusOK, r.releasePayload())
}

func (r *AppRelease) serveUpdate(w http.ResponseWriter, request *http.Request) {
	platform := valueFromQueryOrHeader(request, "platform", "X-App-Platform")
	channel := valueFromQueryOrHeader(request, "channel", "X-App-Channel")
	versionName := valueFromQueryOrHeader(request, "version_name", "X-App-Version-Name")
	versionCodeValue := valueFromQueryOrHeader(request, "version_code", "X-App-Version-Code")
	versionCode, err := strconv.ParseInt(versionCodeValue, 10, 64)
	if platform != "android" || channel != "stable" || strings.TrimSpace(versionName) == "" || err != nil || versionCode <= 0 {
		WriteAppError(w, request, AppError{Status: http.StatusBadRequest, Code: "INVALID_APP_VERSION", Message: "请提供有效的 Android stable 版本信息"})
		return
	}
	updateAvailable := versionCode < r.VersionCode
	updateType := "none"
	if updateAvailable {
		updateType = "optional"
		if versionCode < r.MinimumSupportedVersionCode {
			updateType = "required"
		}
	}
	payload := r.releasePayload()
	payload["current_version_name"] = versionName
	payload["current_version_code"] = versionCode
	payload["update_available"] = updateAvailable
	payload["update_type"] = updateType
	if !updateAvailable {
		payload["download_url"] = ""
	}
	w.Header().Set("Cache-Control", "no-store")
	WriteJSON(w, http.StatusOK, payload)
}

func (r *AppRelease) releasePayload() map[string]any {
	return map[string]any{
		"platform":                       "android",
		"channel":                        "stable",
		"latest_version_name":            r.VersionName,
		"latest_version_code":            r.VersionCode,
		"minimum_supported_version_code": r.MinimumSupportedVersionCode,
		"title":                          r.Title,
		"changelog":                      r.Changelog,
		"file_name":                      r.FileName,
		"file_size":                      r.FileSize,
		"sha256":                         r.SHA256,
		"download_url":                   r.downloadURL(),
		"published_at":                   r.PublishedAt.Format(time.RFC3339),
		"check_after_seconds":            21600,
	}
}

func (r *AppRelease) serveDownload(w http.ResponseWriter, request *http.Request) {
	file, err := os.Open(r.FilePath)
	if err != nil {
		WriteAppError(w, request, AppError{Status: http.StatusServiceUnavailable, Code: "APP_RELEASE_UNAVAILABLE", Message: "安装包暂时不可用"})
		return
	}
	defer file.Close()
	info, err := file.Stat()
	// SHA256/ETag 只在启动算一次。磁盘文件一旦被原地替换（哪怕大小不变），
	// 继续下发就会出现“接口 SHA=旧包、实际下载=新包”；size 与 mtime 任一
	// 对不上就拒绝服务，等重启重新校验清单后再恢复。
	if err != nil || info.Size() != r.FileSize || !info.ModTime().Equal(r.FileModTime) {
		WriteAppError(w, request, AppError{Status: http.StatusServiceUnavailable, Code: "APP_RELEASE_CHANGED", Message: "安装包正在更新，请稍后重试"})
		return
	}
	w.Header().Set("Content-Type", "application/vnd.android.package-archive")
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": r.FileName}))
	w.Header().Set("Accept-Ranges", "bytes")
	w.Header().Set("ETag", `"`+r.SHA256+`"`)
	w.Header().Set("Cache-Control", "public, max-age=3600, immutable")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	http.ServeContent(w, request, r.FileName, info.ModTime(), file)
}

func valueFromQueryOrHeader(request *http.Request, queryKey, headerKey string) string {
	if value := strings.TrimSpace(request.URL.Query().Get(queryKey)); value != "" {
		return value
	}
	return strings.TrimSpace(request.Header.Get(headerKey))
}

func validateReleasePublicBaseURL(value string) error {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return errors.New("app release public base URL must be a complete HTTP(S) URL")
	}
	return nil
}
