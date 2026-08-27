package outbox

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

func createTestJPEG(w, h int) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{R: uint8((x * 255) / w), G: uint8((y * 255) / h), B: 100, A: 255})
		}
	}
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 95})
	return buf.Bytes()
}

func TestNoopHandlerIsIdempotent(t *testing.T) {
	handler := NoopHandler{}
	event := Event{ID: "event-1", EventType: "notification.created", Payload: []byte(`{"id":"n1"}`)}
	if err := handler.Handle(context.Background(), event); err != nil {
		t.Fatal(err)
	}
	if err := handler.Handle(context.Background(), event); err != nil {
		t.Fatal(err)
	}
}

func TestMinCapsBackoffExponent(t *testing.T) {
	if min(9, 8) != 8 || min(3, 8) != 3 {
		t.Fatal(errors.New("min returned unexpected value"))
	}
}

type testCaptureHandler struct {
	called bool
}

func (h *testCaptureHandler) Handle(_ context.Context, _ Event) error {
	h.called = true
	return nil
}

func TestRouterHandlerRoutesByEventType(t *testing.T) {
	router := NewRouterHandler()
	hNotification := &testCaptureHandler{}
	hMedia := &testCaptureHandler{}
	router.Register("notification.created", hNotification)
	router.Register("media.process", hMedia)

	if err := router.Handle(context.Background(), Event{EventType: "media.process"}); err != nil {
		t.Fatal(err)
	}
	if !hMedia.called || hNotification.called {
		t.Fatalf("expected media handler called, got: notification=%v, media=%v", hNotification.called, hMedia.called)
	}
}

func TestRouterHandlerReturnsErrorOnUnknownEvent(t *testing.T) {
	router := NewRouterHandler()
	err := router.Handle(context.Background(), Event{EventType: "unknown.event.type"})
	if err == nil {
		t.Fatal("expected error for unhandled event type, got nil")
	}
}

func TestMediaHandlerProcessDecodesAndGeneratesRealVariants(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	store := storage.NewMemoryStorage()
	ctx := context.Background()

	// 准备 2400x1600 原始图片
	sourceBytes := createTestJPEG(2400, 1600)
	sourceHasher := sha256.New()
	_, _ = sourceHasher.Write(sourceBytes)
	sourceHash := hex.EncodeToString(sourceHasher.Sum(nil))
	sourceKey := "media/u1/m123"

	_ = store.Put(ctx, sourceKey, "image/jpeg", bytes.NewReader(sourceBytes), int64(len(sourceBytes)))

	handler := MediaHandler{
		DB:      db,
		Storage: store,
	}

	payload, _ := json.Marshal(MediaProcessPayload{
		MediaID:   "m123",
		ObjectKey: sourceKey,
		MimeType:  "image/jpeg",
		Width:     2400,
		Height:    1600,
		SizeBytes: int64(len(sourceBytes)),
		SHA256:    sourceHash,
	})

	// 1. 幂等性检查 query
	mock.ExpectQuery(`SELECT COUNT\(\*\) FROM media_variants WHERE media_id = \$1 AND status = 'ready'`).
		WithArgs("m123").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))

	// 2. 事务 Begin
	mock.ExpectBegin()
	// 3. 写入 source
	mock.ExpectExec(`INSERT INTO media_variants .* VALUES \(\$1, 'source'`).
		WithArgs("m123", sourceKey, "image/jpeg", 2400, 1600, int64(len(sourceBytes)), sourceHash, sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 4. 写入 original (2400x1600, 去 EXIF)
	mock.ExpectExec(`INSERT INTO media_variants .* VALUES \(\$1, 'original'`).
		WithArgs("m123", sourceKey+"_original.jpg", 2400, 1600, sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 5. 写入 detail (1440x960)
	mock.ExpectExec(`INSERT INTO media_variants .* VALUES \(\$1, 'detail'`).
		WithArgs("m123", sourceKey+"_detail.jpg", 1440, 960, sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 6. 写入 thumb (640x427)
	mock.ExpectExec(`INSERT INTO media_variants .* VALUES \(\$1, 'thumb'`).
		WithArgs("m123", sourceKey+"_thumb.jpg", 640, 427, sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 7. 事务 Commit
	mock.ExpectCommit()

	if err := handler.Handle(ctx, Event{EventType: "media.process", Payload: payload}); err != nil {
		t.Fatalf("Handle media.process failed: %v", err)
	}

	// 验证 Storage 中是否真实存在 3 个新生成变体
	if !store.HasObject(sourceKey + "_original.jpg") {
		t.Errorf("original variant missing in storage")
	}
	if !store.HasObject(sourceKey + "_detail.jpg") {
		t.Errorf("detail variant missing in storage")
	}
	if !store.HasObject(sourceKey + "_thumb.jpg") {
		t.Errorf("thumb variant missing in storage")
	}

	// 验证 thumb 尺寸与大小
	thumbBytes, ok := store.GetBytes(sourceKey + "_thumb.jpg")
	if !ok || len(thumbBytes) == 0 {
		t.Fatalf("thumb data empty")
	}
	detailBytes, _ := store.GetBytes(sourceKey + "_detail.jpg")
	if len(thumbBytes) >= len(detailBytes) {
		t.Errorf("expected thumb size (%d) < detail size (%d)", len(thumbBytes), len(detailBytes))
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet sqlmock expectations: %v", err)
	}
}

func TestMediaHandlerProcessIdempotency(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := MediaHandler{DB: db}
	payload, _ := json.Marshal(MediaProcessPayload{
		MediaID:   "m_already_ready",
		ObjectKey: "media/u1/ready",
	})

	// 模拟已存在 4 个 ready 变体
	mock.ExpectQuery(`SELECT COUNT\(\*\) FROM media_variants WHERE media_id = \$1 AND status = 'ready'`).
		WithArgs("m_already_ready").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(4))

	// 不应发起任何 INSERT / UPDATE 事务
	if err := handler.Handle(context.Background(), Event{EventType: "media.process", Payload: payload}); err != nil {
		t.Fatalf("Idempotent handle returned error: %v", err)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet sqlmock expectations: %v", err)
	}
}

func TestMediaHandlerProcessReturnsErrorWhenSourceIsMissing(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := MediaHandler{DB: db, Storage: storage.NewMemoryStorage()}
	payload, _ := json.Marshal(MediaProcessPayload{
		MediaID:   "m_missing_source",
		ObjectKey: "media/u1/missing",
		MimeType:  "image/jpeg",
	})
	mock.ExpectQuery(`SELECT COUNT\(\*\) FROM media_variants WHERE media_id = \$1 AND status = 'ready'`).
		WithArgs("m_missing_source").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))

	err = handler.Handle(context.Background(), Event{EventType: "media.process", Payload: payload})
	if err == nil || !strings.Contains(err.Error(), "get source media") {
		t.Fatalf("expected source download error, got %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unexpected database interaction after source failure: %v", err)
	}
}

func TestMediaHandlerProcessReturnsErrorWhenSourceCannotBeDecoded(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	store := storage.NewMemoryStorage()
	if err := store.Put(context.Background(), "media/u1/corrupt", "image/jpeg", bytes.NewReader([]byte("not an image")), 12); err != nil {
		t.Fatal(err)
	}
	handler := MediaHandler{DB: db, Storage: store}
	payload, _ := json.Marshal(MediaProcessPayload{
		MediaID:   "m_corrupt_source",
		ObjectKey: "media/u1/corrupt",
		MimeType:  "image/jpeg",
	})
	mock.ExpectQuery(`SELECT COUNT\(\*\) FROM media_variants WHERE media_id = \$1 AND status = 'ready'`).
		WithArgs("m_corrupt_source").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))

	err = handler.Handle(context.Background(), Event{EventType: "media.process", Payload: payload})
	if err == nil || !strings.Contains(err.Error(), "process image") {
		t.Fatalf("expected image processing error, got %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unexpected database interaction after processing failure: %v", err)
	}
}

func TestMediaHandlerVideoPersistsOnlyVerifiedSourceVariant(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	ctx := context.Background()
	store := storage.NewMemoryStorage()
	const sourceKey = "media/u1/video"
	videoBytes := []byte("valid video bytes")
	if err := store.Put(ctx, sourceKey, "video/mp4", bytes.NewReader(videoBytes), int64(len(videoBytes))); err != nil {
		t.Fatal(err)
	}
	handler := MediaHandler{DB: db, Storage: store}
	payload, _ := json.Marshal(MediaProcessPayload{
		MediaID:   "m_video",
		ObjectKey: sourceKey,
		MimeType:  "video/mp4",
		Width:     1920,
		Height:    1080,
		SizeBytes: int64(len(videoBytes)),
	})

	mock.ExpectQuery(`SELECT COUNT\(\*\) FROM media_variants WHERE media_id = \$1 AND status = 'ready' AND variant IN \('source'\)`).
		WithArgs("m_video").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))
	mock.ExpectBegin()
	mock.ExpectExec(`INSERT INTO media_variants .* VALUES \(\$1, 'source'`).
		WithArgs("m_video", sourceKey, "video/mp4", 1920, 1080, int64(len(videoBytes)), "", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	if err := handler.Handle(ctx, Event{EventType: "media.process", Payload: payload}); err != nil {
		t.Fatalf("Handle video media.process failed: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestMediaHandlerDeletePhysicallyDeletesAllVariants(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	store := storage.NewMemoryStorage()
	ctx := context.Background()

	keys := []string{
		"media/u1/m_del",
		"media/u1/m_del_original.jpg",
		"media/u1/m_del_detail.jpg",
		"media/u1/m_del_thumb.jpg",
	}
	for _, k := range keys {
		_ = store.Put(ctx, k, "image/jpeg", bytes.NewReader([]byte("test")), 4)
	}

	handler := MediaHandler{
		DB:      db,
		Storage: store,
	}

	payload, _ := json.Marshal(MediaDeletePayload{
		MediaID:   "m_del",
		ObjectKey: "media/u1/m_del",
	})

	// 查询该 media 下的所有 variant object keys
	mock.ExpectQuery(`SELECT object_key FROM media_variants WHERE media_id = \$1`).
		WithArgs("m_del").
		WillReturnRows(sqlmock.NewRows([]string{"object_key"}).
			AddRow("media/u1/m_del_original.jpg").
			AddRow("media/u1/m_del_detail.jpg").
			AddRow("media/u1/m_del_thumb.jpg"))

	mock.ExpectExec(`DELETE FROM media_variants WHERE media_id = \$1`).
		WithArgs("m_del").
		WillReturnResult(sqlmock.NewResult(0, 3))

	if err := handler.Handle(ctx, Event{EventType: "media.delete", Payload: payload}); err != nil {
		t.Fatalf("Handle media.delete failed: %v", err)
	}

	// 断言 Storage 中源文件和所有 3 个变体全部已被物理删除
	for _, k := range keys {
		if store.HasObject(k) {
			t.Errorf("expected %s physically deleted from storage", k)
		}
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet sqlmock expectations: %v", err)
	}
}
