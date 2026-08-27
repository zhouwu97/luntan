package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

func TestMediaStorageRejectsMissingUploadedObject(t *testing.T) {
	storageServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.NotFound(w, nil)
	}))
	defer storageServer.Close()

	store := storage.NewHTTPMediaStorage(storageServer.URL, "", "test-secret", "")
	err := store.VerifyUploaded(context.Background(), &storage.MediaAsset{
		ID:        "media-1",
		ObjectKey: "media/user-1/media-1",
		MimeType:  "image/png",
		Size:      128,
		SHA256:    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		Status:    "pending",
	})
	if !errors.Is(err, ErrInvalidMedia) {
		t.Fatalf("VerifyUploaded error = %v, want ErrInvalidMedia", err)
	}
}

func TestMediaStorageRejectsUploadedObjectWithWrongSize(t *testing.T) {
	storageServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Length", "10")
		w.Header().Set("Content-Type", "image/png")
		w.WriteHeader(http.StatusOK)
	}))
	defer storageServer.Close()

	store := storage.NewHTTPMediaStorage(storageServer.URL, "", "test-secret", "")
	err := store.VerifyUploaded(context.Background(), &storage.MediaAsset{
		ID:        "media-1",
		ObjectKey: "media/user-1/media-1",
		MimeType:  "image/png",
		Size:      11,
		SHA256:    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		Status:    "pending",
	})
	if !errors.Is(err, ErrInvalidMedia) {
		t.Fatalf("VerifyUploaded error = %v, want ErrInvalidMedia", err)
	}
}

func TestMediaStorageRejectsUploadedObjectWithWrongMIMEType(t *testing.T) {
	storageServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Length", "10")
		w.Header().Set("Content-Type", "application/octet-stream")
		w.WriteHeader(http.StatusOK)
	}))
	defer storageServer.Close()

	store := storage.NewHTTPMediaStorage(storageServer.URL, "", "test-secret", "")
	err := store.VerifyUploaded(context.Background(), &storage.MediaAsset{
		ID:        "media-1",
		ObjectKey: "media/user-1/media-1",
		MimeType:  "image/png",
		Size:      10,
		SHA256:    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		Status:    "pending",
	})
	if !errors.Is(err, ErrInvalidMedia) {
		t.Fatalf("VerifyUploaded error = %v, want ErrInvalidMedia", err)
	}
}

func TestMediaStorageRejectsUploadedObjectWithWrongChecksum(t *testing.T) {
	storageServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Length", "10")
		w.Header().Set("Content-Type", "image/png")
		w.Header().Set(
			"X-Checksum-Sha256",
			"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		)
		w.WriteHeader(http.StatusOK)
	}))
	defer storageServer.Close()

	store := storage.NewHTTPMediaStorage(storageServer.URL, "", "test-secret", "")
	err := store.VerifyUploaded(context.Background(), &storage.MediaAsset{
		ID:        "media-1",
		ObjectKey: "media/user-1/media-1",
		MimeType:  "image/png",
		Size:      10,
		SHA256:    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		Status:    "pending",
	})
	if !errors.Is(err, ErrInvalidMedia) {
		t.Fatalf("VerifyUploaded error = %v, want ErrInvalidMedia", err)
	}
}

func TestMediaStorageVerifiesUploadedImageBytes(t *testing.T) {
	var object bytes.Buffer
	if err := png.Encode(&object, image.NewRGBA(image.Rect(0, 0, 1, 1))); err != nil {
		t.Fatal(err)
	}
	objectBytes := object.Bytes()
	digest := sha256.Sum256(objectBytes)
	digestHex := hex.EncodeToString(digest[:])
	getCalled := false
	storageServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", strconv.Itoa(len(objectBytes)))
		w.Header().Set("Content-Type", "image/png")
		w.Header().Set("X-Checksum-Sha256", digestHex)
		switch r.Method {
		case http.MethodHead:
			w.WriteHeader(http.StatusOK)
		case http.MethodGet:
			getCalled = true
			_, _ = w.Write(objectBytes)
		default:
			t.Fatalf("unexpected verification method %s", r.Method)
		}
	}))
	defer storageServer.Close()

	store := storage.NewHTTPMediaStorage(storageServer.URL, "", "test-secret", "")
	err := store.VerifyUploaded(context.Background(), &storage.MediaAsset{
		ID:        "media-1",
		ObjectKey: "media/user-1/media-1",
		MimeType:  "image/png",
		Width:     1,
		Height:    1,
		Size:      int64(len(objectBytes)),
		SHA256:    digestHex,
		Status:    "pending",
	})
	if err != nil {
		t.Fatalf("VerifyUploaded error = %v", err)
	}
	if !getCalled {
		t.Fatal("VerifyUploaded must inspect object bytes after HEAD metadata")
	}
}

func TestMediaUploadRequiresSHA256(t *testing.T) {
	if validMediaInput(mediaUploadInput{
		FileName: "a.png",
		MimeType: "image/png",
		Size:     10,
	}) {
		t.Fatal("media upload without SHA-256 must be rejected")
	}
}

func TestNewMediaID(t *testing.T) {
	id, err := newMediaID()
	if err != nil {
		t.Fatalf("newMediaID failed: %v", err)
	}
	if len(id) != 38 || id[:6] != "media_" {
		t.Fatalf("invalid media id: %s", id)
	}
}

func TestMediaInputLimits(t *testing.T) {
	checksum := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	// Image <= 15MB allowed
	if !validMediaInput(mediaUploadInput{
		FileName: "test.png",
		MimeType: "image/png",
		Size:     15 * 1024 * 1024,
		SHA256:   checksum,
	}) {
		t.Fatal("expected 15MB image to be valid")
	}
	// Image > 15MB rejected
	if validMediaInput(mediaUploadInput{
		FileName: "test.png",
		MimeType: "image/png",
		Size:     15*1024*1024 + 1,
		SHA256:   checksum,
	}) {
		t.Fatal("expected >15MB image to be rejected")
	}
	// Pixel area > 40MP rejected
	if validMediaInput(mediaUploadInput{
		FileName: "test.png",
		MimeType: "image/png",
		Size:     1024,
		Width:    7000,
		Height:   6000, // 42 MP
		SHA256:   checksum,
	}) {
		t.Fatal("expected >40MP image to be rejected")
	}
}
