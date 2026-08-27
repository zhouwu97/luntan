package storage

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"image"
	"image/color"
	"image/jpeg"
	"io"
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

func TestMemoryStorageSignUpload(t *testing.T) {
	store := NewMemoryStorage()
	url, err := store.SignUpload(context.Background(), "asset1", "obj1", "image/png", time.Now().Add(5*time.Minute))
	if err != nil || url == "" {
		t.Fatalf("SignUpload failed: url=%s, err=%v", url, err)
	}
}
