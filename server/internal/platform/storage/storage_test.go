package storage

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func createTestJPEG(w, h int) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{R: 200, G: 100, B: 50, A: 255})
		}
	}
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, img, nil)
	return buf.Bytes()
}

func TestMemoryStorageCRUD(t *testing.T) {
	store := NewMemoryStorage()
	ctx := context.Background()

	testBytes := createTestJPEG(100, 100)
	key := "media/u1/test.jpg"

	// Put
	if err := store.Put(ctx, key, "image/jpeg", bytes.NewReader(testBytes), int64(len(testBytes))); err != nil {
		t.Fatalf("Put failed: %v", err)
	}

	// HasObject
	if !store.HasObject(key) {
		t.Fatalf("expected store to have %s", key)
	}

	// Get
	rc, size, mimeType, err := store.Get(ctx, key)
	if err != nil {
		t.Fatalf("Get failed: %v", err)
	}
	defer rc.Close()
	if size != int64(len(testBytes)) || mimeType != "image/jpeg" {
		t.Fatalf("unexpected size/mime: size=%d, mime=%s", size, mimeType)
	}
	readData, err := io.ReadAll(rc)
	if err != nil || len(readData) != len(testBytes) {
		t.Fatalf("read data mismatch")
	}

	// VerifyUploaded
	hasher := sha256.New()
	_, _ = hasher.Write(testBytes)
	hashStr := hex.EncodeToString(hasher.Sum(nil))

	asset := &MediaAsset{
		ID:        "m1",
		ObjectKey: key,
		MimeType:  "image/jpeg",
		Width:     100,
		Height:    100,
		Size:      int64(len(testBytes)),
		SHA256:    hashStr,
		Status:    "pending",
	}
	if err := store.VerifyUploaded(ctx, asset); err != nil {
		t.Fatalf("VerifyUploaded failed: %v", err)
	}

	// Delete
	if err := store.Delete(ctx, key); err != nil {
		t.Fatalf("Delete failed: %v", err)
	}
	if store.HasObject(key) {
		t.Fatalf("expected object deleted")
	}
}

func TestMemoryStorageVerifyUploadedValidatesBytesAndDimensions(t *testing.T) {
	store := NewMemoryStorage()
	ctx := context.Background()
	jpegBytes := createTestJPEG(120, 80)
	digest := sha256.Sum256(jpegBytes)
	key := "media/u1/verified.jpg"
	if err := store.Put(ctx, key, "image/jpeg", bytes.NewReader(jpegBytes), int64(len(jpegBytes))); err != nil {
		t.Fatal(err)
	}

	valid := &MediaAsset{
		ObjectKey: key,
		MimeType:  "image/jpeg",
		Width:     120,
		Height:    80,
		Size:      int64(len(jpegBytes)),
		SHA256:    hex.EncodeToString(digest[:]),
	}
	if err := store.VerifyUploaded(ctx, valid); err != nil {
		t.Fatalf("valid JPEG rejected: %v", err)
	}

	wrongDimensions := *valid
	wrongDimensions.Width = 121
	if err := store.VerifyUploaded(ctx, &wrongDimensions); err != ErrInvalidMedia {
		t.Fatalf("dimension mismatch error = %v, want ErrInvalidMedia", err)
	}

	wrongHash := *valid
	wrongHash.SHA256 = strings.Repeat("0", 64)
	if err := store.VerifyUploaded(ctx, &wrongHash); err != ErrInvalidMedia {
		t.Fatalf("checksum mismatch error = %v, want ErrInvalidMedia", err)
	}

	pngImage := image.NewRGBA(image.Rect(0, 0, 32, 24))
	var pngBuffer bytes.Buffer
	if err := png.Encode(&pngBuffer, pngImage); err != nil {
		t.Fatal(err)
	}
	pngBytes := pngBuffer.Bytes()
	pngDigest := sha256.Sum256(pngBytes)
	pngKey := "media/u1/wrong-mime.png"
	if err := store.Put(ctx, pngKey, "image/jpeg", bytes.NewReader(pngBytes), int64(len(pngBytes))); err != nil {
		t.Fatal(err)
	}
	spoofedMime := &MediaAsset{
		ObjectKey: pngKey,
		MimeType:  "image/jpeg",
		Size:      int64(len(pngBytes)),
		SHA256:    hex.EncodeToString(pngDigest[:]),
	}
	if err := store.VerifyUploaded(ctx, spoofedMime); err != ErrInvalidMedia {
		t.Fatalf("content/MIME mismatch error = %v, want ErrInvalidMedia", err)
	}

	corruptBytes := []byte("this is not an image")
	corruptDigest := sha256.Sum256(corruptBytes)
	corruptKey := "media/u1/corrupt.jpg"
	if err := store.Put(ctx, corruptKey, "image/jpeg", bytes.NewReader(corruptBytes), int64(len(corruptBytes))); err != nil {
		t.Fatal(err)
	}
	corrupt := &MediaAsset{
		ObjectKey: corruptKey,
		MimeType:  "image/jpeg",
		Size:      int64(len(corruptBytes)),
		SHA256:    hex.EncodeToString(corruptDigest[:]),
	}
	if err := store.VerifyUploaded(ctx, corrupt); err != ErrInvalidMedia {
		t.Fatalf("corrupt image error = %v, want ErrInvalidMedia", err)
	}
}

func TestMemoryStorageDeleteMulti(t *testing.T) {
	store := NewMemoryStorage()
	ctx := context.Background()

	keys := []string{"k1", "k2", "k3"}
	for _, k := range keys {
		_ = store.Put(ctx, k, "text/plain", bytes.NewReader([]byte("test")), 4)
	}

	if err := store.DeleteMulti(ctx, keys); err != nil {
		t.Fatalf("DeleteMulti failed: %v", err)
	}
	for _, k := range keys {
		if store.HasObject(k) {
			t.Fatalf("key %s was not deleted", k)
		}
	}
}

func TestHTTPMediaStorageReadsLegacyAbsoluteObjectKey(t *testing.T) {
	data := []byte("legacy-imported-image")
	storageServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			t.Fatalf("unexpected method %s", r.Method)
		}
		if r.URL.Path != "/imported-media/post-1.webp" {
			t.Fatalf("normalized path = %q, want /imported-media/post-1.webp", r.URL.Path)
		}
		w.Header().Set("Content-Type", "image/webp")
		w.Header().Set("Content-Length", "21")
		_, _ = w.Write(data)
	}))
	defer storageServer.Close()

	store := NewHTTPMediaStorage("", storageServer.URL, "test-secret", "")
	rc, size, mimeType, err := store.Get(
		context.Background(),
		"http://43.161.249.91/imported-media/post-1.webp",
	)
	if err != nil {
		t.Fatalf("Get legacy absolute object key failed: %v", err)
	}
	defer rc.Close()
	if size != int64(len(data)) || mimeType != "image/webp" {
		t.Fatalf("unexpected response metadata: size=%d mime=%q", size, mimeType)
	}
}

func TestMemoryStorageSignUpload(t *testing.T) {
	store := NewMemoryStorage()
	url, err := store.SignUpload(context.Background(), "asset1", "obj1", "image/png", time.Now().Add(5*time.Minute))
	if err != nil || url == "" {
		t.Fatalf("SignUpload failed: url=%s, err=%v", url, err)
	}
}

func TestObjectStorageFromEnvUsesLocalDiskForConfiguredQAStorage(t *testing.T) {
	t.Setenv("OBJECT_STORAGE_UPLOAD_BASE_URL", "")
	t.Setenv("OBJECT_STORAGE_SIGNING_SECRET", "local-test-secret")
	t.Setenv("MEDIA_STORAGE_DIR", t.TempDir())

	store := NewObjectStorageFromEnv()
	if _, err := store.SignUpload(context.Background(), "asset1", "media/u1/asset1", "image/png", time.Now().Add(5*time.Minute)); err != nil {
		t.Fatalf("configured local media storage should issue an upload URL, got: %v", err)
	}
}

func TestLocalMediaStorageSignedUploadAndVerify(t *testing.T) {
	store := NewLocalMediaStorage(t.TempDir(), "local-test-secret")
	data := createTestJPEG(100, 80)
	digest := sha256.Sum256(data)
	digestHex := hex.EncodeToString(digest[:])
	expiresAt := time.Now().Add(5 * time.Minute)
	uploadURL, err := store.SignUpload(context.Background(), "asset1", "media/u1/asset1", "image/jpeg", expiresAt)
	if err != nil {
		t.Fatalf("SignUpload failed: %v", err)
	}

	req := httptest.NewRequest(http.MethodPut, uploadURL, bytes.NewReader(data))
	req.Header.Set("Content-Type", "image/jpeg")
	res := httptest.NewRecorder()
	store.ServeSignedUpload(res, req)
	if res.Code != http.StatusNoContent {
		t.Fatalf("signed upload status = %d, body=%s", res.Code, res.Body.String())
	}

	asset := &MediaAsset{
		ID:        "asset1",
		ObjectKey: "media/u1/asset1",
		MimeType:  "image/jpeg",
		Width:     100,
		Height:    80,
		Size:      int64(len(data)),
		SHA256:    digestHex,
		Status:    "pending",
	}
	if err := store.VerifyUploaded(context.Background(), asset); err != nil {
		t.Fatalf("VerifyUploaded failed: %v", err)
	}
	filePath, err := store.objectPath(asset.ObjectKey)
	if err != nil {
		t.Fatalf("resolve stored object path: %v", err)
	}
	info, err := os.Stat(filePath)
	if err != nil {
		t.Fatalf("stat stored object: %v", err)
	}
	if info.Mode().Perm()&0444 == 0 {
		t.Fatalf("stored object is not readable: permissions = %o", info.Mode().Perm())
	}
	for _, directory := range []string{
		filepath.Dir(filePath),
		filepath.Dir(filepath.Dir(filePath)),
	} {
		directoryInfo, statErr := os.Stat(directory)
		if statErr != nil {
			t.Fatalf("stat object directory: %v", statErr)
		}
		if directoryInfo.Mode().Perm()&0111 == 0 {
			t.Fatalf("object directory is not traversable: %s permissions=%o", directory, directoryInfo.Mode().Perm())
		}
	}
}
