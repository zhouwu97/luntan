package storage

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	ErrStorageUnavailable = errors.New("media storage unavailable")
	ErrObjectNotFound     = errors.New("object not found")
	ErrInvalidMedia       = errors.New("invalid media")
)

type MediaAsset struct {
	ID        string
	ObjectKey string
	MimeType  string
	Width     int
	Height    int
	Size      int64
	SHA256    string
	Status    string
}

type ObjectStorage interface {
	SignUpload(ctx context.Context, assetID, objectKey, mimeType string, expiresAt time.Time) (string, error)
	VerifyUploaded(ctx context.Context, asset *MediaAsset) error
	Get(ctx context.Context, objectKey string) (io.ReadCloser, int64, string, error)
	Put(ctx context.Context, objectKey string, mimeType string, reader io.Reader, size int64) error
	Delete(ctx context.Context, objectKey string) error
	DeleteMulti(ctx context.Context, objectKeys []string) error
}

type MemoryStorage struct {
	mu      sync.RWMutex
	objects map[string]storedObject
}

type storedObject struct {
	data     []byte
	mimeType string
}

func NewMemoryStorage() *MemoryStorage {
	return &MemoryStorage{
		objects: make(map[string]storedObject),
	}
}

func (m *MemoryStorage) SignUpload(_ context.Context, assetID, objectKey, mimeType string, expiresAt time.Time) (string, error) {
	return fmt.Sprintf("memory://upload/%s?asset_id=%s&mime_type=%s&expires=%d", objectKey, assetID, mimeType, expiresAt.Unix()), nil
}

func (m *MemoryStorage) VerifyUploaded(_ context.Context, asset *MediaAsset) error {
	m.mu.RLock()
	obj, ok := m.objects[asset.ObjectKey]
	m.mu.RUnlock()
	if !ok {
		return ErrInvalidMedia
	}
	if int64(len(obj.data)) != asset.Size {
		return ErrInvalidMedia
	}
	hasher := sha256.New()
	_, _ = hasher.Write(obj.data)
	actualHash := hex.EncodeToString(hasher.Sum(nil))
	if !strings.EqualFold(actualHash, asset.SHA256) {
		return ErrInvalidMedia
	}
	if err := verifyMediaContent(obj.data, asset); err != nil {
		return err
	}
	return nil
}

func (m *MemoryStorage) Get(_ context.Context, objectKey string) (io.ReadCloser, int64, string, error) {
	m.mu.RLock()
	obj, ok := m.objects[objectKey]
	m.mu.RUnlock()
	if !ok {
		return nil, 0, "", ErrObjectNotFound
	}
	dataCopy := make([]byte, len(obj.data))
	copy(dataCopy, obj.data)
	return io.NopCloser(bytes.NewReader(dataCopy)), int64(len(dataCopy)), obj.mimeType, nil
}

func (m *MemoryStorage) Put(_ context.Context, objectKey string, mimeType string, reader io.Reader, _ int64) error {
	data, err := io.ReadAll(reader)
	if err != nil {
		return err
	}
	m.mu.Lock()
	m.objects[objectKey] = storedObject{
		data:     data,
		mimeType: mimeType,
	}
	m.mu.Unlock()
	return nil
}

func (m *MemoryStorage) Delete(_ context.Context, objectKey string) error {
	m.mu.Lock()
	delete(m.objects, objectKey)
	m.mu.Unlock()
	return nil
}

func (m *MemoryStorage) DeleteMulti(ctx context.Context, objectKeys []string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, key := range objectKeys {
		delete(m.objects, key)
	}
	return nil
}

func (m *MemoryStorage) HealthCheck(context.Context) error { return nil }

func (m *MemoryStorage) HasObject(objectKey string) bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	_, ok := m.objects[objectKey]
	return ok
}

func (m *MemoryStorage) GetBytes(objectKey string) ([]byte, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	obj, ok := m.objects[objectKey]
	if !ok {
		return nil, false
	}
	data := make([]byte, len(obj.data))
	copy(data, obj.data)
	return data, true
}

type HTTPMediaStorage struct {
	uploadBaseURL   string
	internalBaseURL string
	secret          []byte
	deleteSecret    string
	httpClient      *http.Client
}

func NewHTTPMediaStorage(uploadBaseURL, internalBaseURL, secret, deleteSecret string) *HTTPMediaStorage {
	if uploadBaseURL == "" && internalBaseURL == "" {
		return nil
	}
	return &HTTPMediaStorage{
		uploadBaseURL:   strings.TrimRight(uploadBaseURL, "/"),
		internalBaseURL: strings.TrimRight(internalBaseURL, "/"),
		secret:          []byte(secret),
		deleteSecret:    deleteSecret,
		httpClient:      &http.Client{Timeout: 30 * time.Second},
	}
}

func NewObjectStorageFromEnv() ObjectStorage {
	uploadURL := strings.TrimSpace(os.Getenv("OBJECT_STORAGE_UPLOAD_BASE_URL"))
	secret := strings.TrimSpace(os.Getenv("OBJECT_STORAGE_SIGNING_SECRET"))
	internalURL := strings.TrimSpace(os.Getenv("STORAGE_INTERNAL_BASE_URL"))
	deleteSecret := strings.TrimSpace(os.Getenv("STORAGE_DELETE_SECRET"))
	if uploadURL != "" || internalURL != "" {
		return NewHTTPMediaStorage(uploadURL, internalURL, secret, deleteSecret)
	}
	if localDir := strings.TrimSpace(os.Getenv("MEDIA_STORAGE_DIR")); localDir != "" {
		return NewLocalMediaStorage(localDir, secret)
	}
	return UnavailableMediaStorage{}
}

// normalizeHTTPObjectKey 将历史导入数据中的绝对媒体 URL 归一为对象路径。
// 旧数据可能保存为 http(s)://旧域名/imported-media/...，而 HTTP 存储适配器
// 只能把路径拼接到受控的内部存储地址上；绝不能直接信任数据库中的 host，
// 否则既会拼出错误路径，也会让存储读取具备 SSRF 风险。
func normalizeHTTPObjectKey(objectKey string) string {
	raw := strings.TrimSpace(objectKey)
	if parsed, err := url.Parse(raw); err == nil && parsed.IsAbs() && parsed.Host != "" {
		return strings.TrimLeft(parsed.EscapedPath(), "/")
	}
	return strings.TrimLeft(raw, "/")
}

type UnavailableMediaStorage struct{}

func (UnavailableMediaStorage) SignUpload(context.Context, string, string, string, time.Time) (string, error) {
	return "", ErrStorageUnavailable
}

func (UnavailableMediaStorage) VerifyUploaded(context.Context, *MediaAsset) error {
	return ErrStorageUnavailable
}

func (UnavailableMediaStorage) Get(context.Context, string) (io.ReadCloser, int64, string, error) {
	return nil, 0, "", ErrStorageUnavailable
}

func (UnavailableMediaStorage) Put(context.Context, string, string, io.Reader, int64) error {
	return ErrStorageUnavailable
}

func (UnavailableMediaStorage) Delete(context.Context, string) error {
	return ErrStorageUnavailable
}

func (UnavailableMediaStorage) DeleteMulti(context.Context, []string) error {
	return ErrStorageUnavailable
}

func (UnavailableMediaStorage) HealthCheck(context.Context) error {
	return ErrStorageUnavailable
}

func (s *HTTPMediaStorage) SignUpload(_ context.Context, assetID, objectKey, mimeType string, expiresAt time.Time) (string, error) {
	if s.uploadBaseURL == "" || len(s.secret) == 0 {
		return "", ErrStorageUnavailable
	}
	objectKey = normalizeHTTPObjectKey(objectKey)
	expires := strconv.FormatInt(expiresAt.Unix(), 10)
	message := assetID + "|" + objectKey + "|" + expires
	hash := hmac.New(sha256.New, s.secret)
	_, _ = hash.Write([]byte(message))
	signature := hex.EncodeToString(hash.Sum(nil))
	return s.uploadBaseURL + "?" + url.Values{
		"asset_id":   {assetID},
		"object_key": {objectKey},
		"mime_type":  {mimeType},
		"expires":    {expires},
		"signature":  {signature},
	}.Encode(), nil
}

func (s *HTTPMediaStorage) VerifyUploaded(ctx context.Context, asset *MediaAsset) error {
	if s.uploadBaseURL == "" || len(s.secret) == 0 {
		return ErrStorageUnavailable
	}
	if asset.Status == "deleted" {
		return ErrInvalidMedia
	}
	verificationURL, err := s.SignUpload(
		ctx,
		asset.ID,
		asset.ObjectKey,
		asset.MimeType,
		time.Now().UTC().Add(5*time.Minute),
	)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, verificationURL, nil)
	if err != nil {
		return ErrStorageUnavailable
	}
	client := s.httpClient
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	response, err := client.Do(req)
	if err != nil {
		return ErrStorageUnavailable
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusNotFound {
		return ErrInvalidMedia
	}
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return ErrStorageUnavailable
	}
	if response.ContentLength < 0 || response.ContentLength != asset.Size {
		return ErrInvalidMedia
	}
	contentType, _, err := mime.ParseMediaType(response.Header.Get("Content-Type"))
	if err != nil || !strings.EqualFold(contentType, asset.MimeType) {
		return ErrInvalidMedia
	}
	if checksum := strings.TrimSpace(response.Header.Get("X-Checksum-Sha256")); checksum != "" && (len(checksum) != 64 || !isHex(checksum) || !strings.EqualFold(checksum, asset.SHA256)) {
		return ErrInvalidMedia
	}
	_ = response.Body.Close()

	getRequest, err := http.NewRequestWithContext(ctx, http.MethodGet, verificationURL, nil)
	if err != nil {
		return ErrStorageUnavailable
	}
	getResponse, err := client.Do(getRequest)
	if err != nil {
		return ErrStorageUnavailable
	}
	defer getResponse.Body.Close()
	if getResponse.StatusCode == http.StatusNotFound {
		return ErrInvalidMedia
	}
	if getResponse.StatusCode < http.StatusOK || getResponse.StatusCode >= http.StatusMultipleChoices {
		return ErrStorageUnavailable
	}

	hasher := sha256.New()
	prefix := &limitedPrefixWriter{remaining: 1 << 20}
	written, err := io.Copy(
		io.MultiWriter(hasher, prefix),
		io.LimitReader(getResponse.Body, asset.Size+1),
	)
	if err != nil {
		return ErrStorageUnavailable
	}
	if written != asset.Size || !strings.EqualFold(hex.EncodeToString(hasher.Sum(nil)), asset.SHA256) {
		return ErrInvalidMedia
	}
	if err := verifyMediaContent(prefix.Bytes(), asset); err != nil {
		return err
	}
	return nil
}

func (s *HTTPMediaStorage) Get(ctx context.Context, objectKey string) (io.ReadCloser, int64, string, error) {
	objectKey = normalizeHTTPObjectKey(objectKey)
	var getURL string
	if s.internalBaseURL != "" {
		getURL = s.internalBaseURL + "/" + strings.TrimLeft(objectKey, "/")
	} else {
		signed, err := s.SignUpload(ctx, "internal_get", objectKey, "application/octet-stream", time.Now().UTC().Add(10*time.Minute))
		if err != nil {
			return nil, 0, "", err
		}
		getURL = signed
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, getURL, nil)
	if err != nil {
		return nil, 0, "", err
	}
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, 0, "", err
	}
	if resp.StatusCode == http.StatusNotFound {
		_ = resp.Body.Close()
		return nil, 0, "", ErrObjectNotFound
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		_ = resp.Body.Close()
		return nil, 0, "", fmt.Errorf("storage get %s returned status %d", objectKey, resp.StatusCode)
	}
	mimeType := resp.Header.Get("Content-Type")
	return resp.Body, resp.ContentLength, mimeType, nil
}

func (s *HTTPMediaStorage) Put(ctx context.Context, objectKey string, mimeType string, reader io.Reader, size int64) error {
	objectKey = normalizeHTTPObjectKey(objectKey)
	var putURL string
	if s.internalBaseURL != "" {
		putURL = s.internalBaseURL + "/" + strings.TrimLeft(objectKey, "/")
	} else {
		signed, err := s.SignUpload(ctx, "internal_put", objectKey, mimeType, time.Now().UTC().Add(10*time.Minute))
		if err != nil {
			return err
		}
		putURL = signed
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, putURL, reader)
	if err != nil {
		return err
	}
	if size > 0 {
		req.ContentLength = size
	}
	if mimeType != "" {
		req.Header.Set("Content-Type", mimeType)
	}
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("storage put %s returned status %d", objectKey, resp.StatusCode)
	}
	return nil
}

func (s *HTTPMediaStorage) Delete(ctx context.Context, objectKey string) error {
	objectKey = normalizeHTTPObjectKey(objectKey)
	var deleteURL string
	if s.internalBaseURL != "" {
		deleteURL = s.internalBaseURL + "/" + strings.TrimLeft(objectKey, "/")
	} else {
		deleteURL = s.uploadBaseURL + "/" + strings.TrimLeft(objectKey, "/")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, deleteURL, nil)
	if err != nil {
		return err
	}
	if s.deleteSecret != "" {
		req.Header.Set("X-Delete-Secret", s.deleteSecret)
	}
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound || (resp.StatusCode >= 200 && resp.StatusCode < 300) {
		return nil
	}
	return fmt.Errorf("storage delete %s returned status %d", objectKey, resp.StatusCode)
}

func (s *HTTPMediaStorage) DeleteMulti(ctx context.Context, objectKeys []string) error {
	var firstErr error
	for _, key := range objectKeys {
		if strings.TrimSpace(key) == "" {
			continue
		}
		if err := s.Delete(ctx, key); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

// HealthCheck 通过一次对探测键的低成本请求验证存储链路真实可达：
// 2xx 或 404（探测键不存在）视为可用；401/403 说明签名配置失效，5xx 与
// 网络错误说明存储服务当前不可用。就绪探测必须能暴露“配置存在但服务挂了”。
func (s *HTTPMediaStorage) HealthCheck(ctx context.Context) error {
	if s == nil || (s.uploadBaseURL == "" && s.internalBaseURL == "") {
		return ErrStorageUnavailable
	}
	const probeKey = ".readiness-probe"
	var probeURL string
	if s.internalBaseURL != "" {
		probeURL = s.internalBaseURL + "/" + probeKey
	} else {
		if len(s.secret) == 0 {
			return ErrStorageUnavailable
		}
		signed, err := s.SignUpload(ctx, "readiness", probeKey, "application/octet-stream", time.Now().UTC().Add(time.Minute))
		if err != nil {
			return err
		}
		probeURL = signed
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, probeURL, nil)
	if err != nil {
		return ErrStorageUnavailable
	}
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return ErrStorageUnavailable
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound ||
		(resp.StatusCode >= http.StatusOK && resp.StatusCode < http.StatusMultipleChoices) {
		return nil
	}
	return fmt.Errorf("storage health probe returned status %d", resp.StatusCode)
}

// SignedUploadHandler 是内置本地媒体存储接收客户端直传请求所需的最小接口。
// 外部对象存储仍由其自身的上传地址处理，不会进入该接口。
type SignedUploadHandler interface {
	ServeSignedUpload(http.ResponseWriter, *http.Request)
}

// LocalMediaStorage 为开发/QA 环境提供受签名保护的本地媒体存储。
// 它的上传 URL 使用 API 的相对路径，避免把服务器内网地址暴露给客户端；
// 正式生产环境仍应配置对象存储，避免单机磁盘成为容量和可用性瓶颈。
type LocalMediaStorage struct {
	root   string
	secret []byte
}

func NewLocalMediaStorage(rootDir, secret string) *LocalMediaStorage {
	return &LocalMediaStorage{
		root:   filepath.Clean(strings.TrimSpace(rootDir)),
		secret: []byte(strings.TrimSpace(secret)),
	}
}

func (s *LocalMediaStorage) SignUpload(_ context.Context, assetID, objectKey, mimeType string, expiresAt time.Time) (string, error) {
	if s == nil || strings.TrimSpace(s.root) == "" || len(s.secret) == 0 {
		return "", ErrStorageUnavailable
	}
	if _, err := s.objectPath(objectKey); err != nil {
		return "", ErrInvalidMedia
	}
	expires := strconv.FormatInt(expiresAt.Unix(), 10)
	return "/api/v1/media/upload?" + url.Values{
		"asset_id":   {assetID},
		"object_key": {objectKey},
		"mime_type":  {mimeType},
		"expires":    {expires},
		"signature":  {s.uploadSignature(assetID, objectKey, expires)},
	}.Encode(), nil
}

// ServeSignedUpload 校验上传凭证后将请求体原子写入本地媒体目录。
// 该接口不依赖登录态，安全性来自短时效 HMAC 签名；签名不包含文件内容，
// 完整性和 MIME/尺寸校验继续由 completeMedia 的 VerifyUploaded 执行。
func (s *LocalMediaStorage) ServeSignedUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPut {
		w.Header().Set("Allow", http.MethodPut)
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if s == nil || len(s.secret) == 0 {
		http.Error(w, "media storage unavailable", http.StatusServiceUnavailable)
		return
	}
	query := r.URL.Query()
	assetID := strings.TrimSpace(query.Get("asset_id"))
	objectKey := query.Get("object_key")
	mimeType := strings.TrimSpace(query.Get("mime_type"))
	expiresText := strings.TrimSpace(query.Get("expires"))
	signature := strings.TrimSpace(query.Get("signature"))
	if assetID == "" || mimeType == "" || expiresText == "" || signature == "" {
		http.Error(w, "invalid upload signature", http.StatusForbidden)
		return
	}
	expires, err := strconv.ParseInt(expiresText, 10, 64)
	if err != nil || time.Now().UTC().After(time.Unix(expires, 0)) {
		http.Error(w, "upload signature expired", http.StatusForbidden)
		return
	}
	expected := s.uploadSignature(assetID, objectKey, expiresText)
	if len(signature) != len(expected) || subtle.ConstantTimeCompare([]byte(signature), []byte(expected)) != 1 {
		http.Error(w, "invalid upload signature", http.StatusForbidden)
		return
	}
	if _, err := s.objectPath(objectKey); err != nil {
		http.Error(w, "invalid object key", http.StatusForbidden)
		return
	}
	if contentType := strings.TrimSpace(r.Header.Get("Content-Type")); contentType != "" {
		parsed, _, parseErr := mime.ParseMediaType(contentType)
		if parseErr != nil || !strings.EqualFold(parsed, mimeType) {
			http.Error(w, "content type does not match upload signature", http.StatusBadRequest)
			return
		}
	}
	if r.ContentLength > maxLocalUploadBytes {
		http.Error(w, "uploaded media is too large", http.StatusRequestEntityTooLarge)
		return
	}
	if err := s.writeObject(objectKey, r.Body, r.ContentLength); err != nil {
		if errors.Is(err, ErrInvalidMedia) {
			http.Error(w, "uploaded media is too large", http.StatusRequestEntityTooLarge)
			return
		}
		http.Error(w, "could not store uploaded media", http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

const maxLocalUploadBytes int64 = 100 * 1024 * 1024

func (s *LocalMediaStorage) VerifyUploaded(_ context.Context, asset *MediaAsset) error {
	if s == nil || asset == nil {
		return ErrInvalidMedia
	}
	filePath, err := s.objectPath(asset.ObjectKey)
	if err != nil {
		return ErrInvalidMedia
	}
	file, err := os.Open(filePath)
	if errors.Is(err, os.ErrNotExist) {
		return ErrInvalidMedia
	}
	if err != nil {
		return ErrStorageUnavailable
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return ErrStorageUnavailable
	}
	if !info.Mode().IsRegular() || info.Size() != asset.Size {
		return ErrInvalidMedia
	}
	hasher := sha256.New()
	prefix := &limitedPrefixWriter{remaining: 1 << 20}
	written, err := io.Copy(io.MultiWriter(hasher, prefix), io.LimitReader(file, asset.Size+1))
	if err != nil {
		return ErrStorageUnavailable
	}
	if written != asset.Size || !strings.EqualFold(hex.EncodeToString(hasher.Sum(nil)), asset.SHA256) {
		return ErrInvalidMedia
	}
	return verifyMediaContent(prefix.Bytes(), asset)
}

func (s *LocalMediaStorage) Get(_ context.Context, objectKey string) (io.ReadCloser, int64, string, error) {
	if s == nil {
		return nil, 0, "", ErrStorageUnavailable
	}
	filePath, err := s.objectPath(objectKey)
	if err != nil {
		return nil, 0, "", ErrInvalidMedia
	}
	file, err := os.Open(filePath)
	if errors.Is(err, os.ErrNotExist) {
		return nil, 0, "", ErrObjectNotFound
	}
	if err != nil {
		return nil, 0, "", ErrStorageUnavailable
	}
	info, err := file.Stat()
	if err != nil {
		_ = file.Close()
		return nil, 0, "", ErrStorageUnavailable
	}
	contentType := mime.TypeByExtension(filepath.Ext(objectKey))
	if contentType == "" {
		var prefix [512]byte
		read, readErr := file.Read(prefix[:])
		if readErr != nil && !errors.Is(readErr, io.EOF) {
			_ = file.Close()
			return nil, 0, "", ErrStorageUnavailable
		}
		contentType = http.DetectContentType(prefix[:read])
		if _, seekErr := file.Seek(0, io.SeekStart); seekErr != nil {
			_ = file.Close()
			return nil, 0, "", ErrStorageUnavailable
		}
	}
	return file, info.Size(), contentType, nil
}

func (s *LocalMediaStorage) Put(_ context.Context, objectKey, _ string, reader io.Reader, size int64) error {
	if s == nil {
		return ErrStorageUnavailable
	}
	return s.writeObject(objectKey, reader, size)
}

func (s *LocalMediaStorage) Delete(_ context.Context, objectKey string) error {
	if s == nil {
		return ErrStorageUnavailable
	}
	filePath, err := s.objectPath(objectKey)
	if err != nil {
		return ErrInvalidMedia
	}
	if err := os.Remove(filePath); errors.Is(err, os.ErrNotExist) {
		return nil
	} else if err != nil {
		return ErrStorageUnavailable
	}
	return nil
}

func (s *LocalMediaStorage) DeleteMulti(ctx context.Context, objectKeys []string) error {
	var firstErr error
	for _, objectKey := range objectKeys {
		if strings.TrimSpace(objectKey) == "" {
			continue
		}
		if err := s.Delete(ctx, objectKey); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

func (s *LocalMediaStorage) HealthCheck(_ context.Context) error {
	if s == nil || strings.TrimSpace(s.root) == "" {
		return ErrStorageUnavailable
	}
	info, err := os.Stat(s.root)
	if err != nil || !info.IsDir() {
		return ErrStorageUnavailable
	}
	return nil
}

func (s *LocalMediaStorage) uploadSignature(assetID, objectKey, expires string) string {
	hash := hmac.New(sha256.New, s.secret)
	_, _ = hash.Write([]byte(assetID + "|" + objectKey + "|" + expires))
	return hex.EncodeToString(hash.Sum(nil))
}

func (s *LocalMediaStorage) objectPath(objectKey string) (string, error) {
	key := strings.TrimSpace(objectKey)
	if key == "" || strings.Contains(key, "\\") {
		return "", ErrInvalidMedia
	}
	cleaned := path.Clean(key)
	if cleaned != key || cleaned == "." || cleaned == ".." || strings.HasPrefix(cleaned, "../") || strings.HasPrefix(cleaned, "/") {
		return "", ErrInvalidMedia
	}
	root, err := filepath.Abs(s.root)
	if err != nil {
		return "", ErrStorageUnavailable
	}
	candidate, err := filepath.Abs(filepath.Join(root, filepath.FromSlash(cleaned)))
	if err != nil {
		return "", ErrStorageUnavailable
	}
	relative, err := filepath.Rel(root, candidate)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(os.PathSeparator)) || filepath.IsAbs(relative) {
		return "", ErrInvalidMedia
	}
	return candidate, nil
}

func (s *LocalMediaStorage) writeObject(objectKey string, reader io.Reader, expectedSize int64) error {
	filePath, err := s.objectPath(objectKey)
	if err != nil {
		return ErrInvalidMedia
	}
	if err := os.MkdirAll(filepath.Dir(filePath), 0755); err != nil {
		return ErrStorageUnavailable
	}
	// 用户媒体会由 Nginx 作为公开帖子内容读取，根目录到对象目录都需要可遍历。
	if err := s.makePublicDirs(filepath.Dir(filePath)); err != nil {
		return ErrStorageUnavailable
	}
	temporary, err := os.CreateTemp(s.root, ".media-upload-*")
	if err != nil {
		return ErrStorageUnavailable
	}
	temporaryName := temporary.Name()
	removeTemporary := true
	defer func() {
		_ = temporary.Close()
		if removeTemporary {
			_ = os.Remove(temporaryName)
		}
	}()
	written, err := io.Copy(temporary, io.LimitReader(reader, maxLocalUploadBytes+1))
	if err != nil {
		return ErrStorageUnavailable
	}
	if written > maxLocalUploadBytes || (expectedSize >= 0 && written != expectedSize) {
		return ErrInvalidMedia
	}
	if err := temporary.Close(); err != nil {
		return ErrStorageUnavailable
	}
	if err := os.Chmod(temporaryName, 0644); err != nil {
		return ErrStorageUnavailable
	}
	if err := os.Rename(temporaryName, filePath); err != nil {
		return ErrStorageUnavailable
	}
	removeTemporary = false
	return nil
}

func (s *LocalMediaStorage) makePublicDirs(directory string) error {
	root, err := filepath.Abs(s.root)
	if err != nil {
		return err
	}
	current, err := filepath.Abs(directory)
	if err != nil {
		return err
	}
	for {
		if err := os.Chmod(current, 0755); err != nil {
			return err
		}
		if current == root {
			return nil
		}
		parent := filepath.Dir(current)
		if parent == current {
			return ErrInvalidMedia
		}
		current = parent
	}
}

type limitedPrefixWriter struct {
	buffer    bytes.Buffer
	remaining int
}

func (w *limitedPrefixWriter) Write(value []byte) (int, error) {
	length := len(value)
	if w.remaining <= 0 {
		return length, nil
	}
	toWrite := value
	if len(toWrite) > w.remaining {
		toWrite = toWrite[:w.remaining]
	}
	_, _ = w.buffer.Write(toWrite)
	w.remaining -= len(toWrite)
	return length, nil
}

func (w *limitedPrefixWriter) Bytes() []byte { return w.buffer.Bytes() }

func detectedMediaType(prefix []byte) string {
	// Go 标准库的 DetectContentType 对部分 WebP 文件返回
	// application/octet-stream；WebP 的 RIFF/WEBP 文件头是稳定的，先做
	// 精确识别，再交给标准库处理 JPEG、PNG 和视频等其他格式。
	if len(prefix) >= 12 && string(prefix[:4]) == "RIFF" && string(prefix[8:12]) == "WEBP" {
		return "image/webp"
	}
	return http.DetectContentType(prefix)
}

func verifyMediaContent(prefix []byte, asset *MediaAsset) error {
	detected, _, err := mime.ParseMediaType(detectedMediaType(prefix))
	if err != nil || !strings.EqualFold(detected, asset.MimeType) {
		return ErrInvalidMedia
	}
	if !strings.HasPrefix(asset.MimeType, "image/") {
		return nil
	}

	var width, height int
	if asset.MimeType == "image/webp" {
		width, height, err = WebPDimensions(prefix)
	} else {
		var config image.Config
		config, _, err = image.DecodeConfig(bytes.NewReader(prefix))
		width, height = config.Width, config.Height
	}
	if err != nil || width <= 0 || height <= 0 {
		return ErrInvalidMedia
	}
	if int64(width)*int64(height) > 40_000_000 {
		return ErrInvalidMedia
	}
	if (asset.Width > 0 && asset.Width != width) || (asset.Height > 0 && asset.Height != height) {
		return ErrInvalidMedia
	}
	asset.Width = width
	asset.Height = height
	return nil
}

func WebPDimensions(value []byte) (int, int, error) {
	if len(value) < 30 || string(value[:4]) != "RIFF" || string(value[8:12]) != "WEBP" {
		return 0, 0, ErrInvalidMedia
	}
	switch string(value[12:16]) {
	case "VP8X":
		width := 1 + int(value[24]) + int(value[25])<<8 + int(value[26])<<16
		height := 1 + int(value[27]) + int(value[28])<<8 + int(value[29])<<16
		return width, height, nil
	case "VP8L":
		if len(value) < 25 || value[20] != 0x2f {
			return 0, 0, ErrInvalidMedia
		}
		width := 1 + int(value[21]) + int(value[22]&0x3f)<<8
		height := 1 + int(value[22]>>6) + int(value[23])<<2 + int(value[24]&0x0f)<<10
		return width, height, nil
	case "VP8 ":
		if len(value) < 30 || value[23] != 0x9d || value[24] != 0x01 || value[25] != 0x2a {
			return 0, 0, ErrInvalidMedia
		}
		width := int(value[26]) | int(value[27]&0x3f)<<8
		height := int(value[28]) | int(value[29]&0x3f)<<8
		return width, height, nil
	default:
		return 0, 0, ErrInvalidMedia
	}
}

func isHex(value string) bool {
	_, err := hex.DecodeString(value)
	return err == nil
}
