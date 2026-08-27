package storage

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
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
	if uploadURL == "" && internalURL == "" {
		return UnavailableMediaStorage{}
	}
	return NewHTTPMediaStorage(uploadURL, internalURL, secret, deleteSecret)
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

func (s *HTTPMediaStorage) SignUpload(_ context.Context, assetID, objectKey, mimeType string, expiresAt time.Time) (string, error) {
	if s.uploadBaseURL == "" || len(s.secret) == 0 {
		return "", ErrStorageUnavailable
	}
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

func verifyMediaContent(prefix []byte, asset *MediaAsset) error {
	detected, _, err := mime.ParseMediaType(http.DetectContentType(prefix))
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
