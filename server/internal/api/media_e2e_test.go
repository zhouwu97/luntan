package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/outbox"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

func createReal2400x1600JPEG() []byte {
	w, h := 2400, 1600
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{
				R: uint8((x * 255) / w),
				G: uint8((y * 255) / h),
				B: 120,
				A: 255,
			})
		}
	}
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 92})
	return buf.Bytes()
}

func TestMediaLifecycleAndVariantsEndToEnd(t *testing.T) {
	rawJPEG := createReal2400x1600JPEG()
	hasher := sha256.New()
	_, _ = hasher.Write(rawJPEG)
	rawHash := hex.EncodeToString(hasher.Sum(nil))
	rawSize := int64(len(rawJPEG))

	store := storage.NewMemoryStorage()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	testUser := auth.User{
		ID:          "user-e2e",
		Username:    "author",
		AccountType: "user",
		Status:      "active",
	}

	handler := NewHandlerWithMedia(db, nil, store)

	// Step 1: 模拟已上传到 MemoryStorage
	objectKey := "media/user-e2e/media_e2e_123"
	_ = store.Put(context.Background(), objectKey, "image/jpeg", bytes.NewReader(rawJPEG), rawSize)

	// Step 2: 模拟调用 POST /api/v1/media/media_e2e_123/complete
	// 鉴权查询 auth token
	mock.ExpectQuery(`SELECT u\.id, u\.username, u\.status, COALESCE\(up\.nickname.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).
			AddRow(testUser.ID, testUser.Username, testUser.Status, "Author", 1, 0, testUser.AccountType, "test@example.com", false, nil, false))

	// 查询 media_assets
	mock.ExpectQuery(`SELECT id, owner_id, object_key, original_name, mime_type, width, height, size, sha256, status, created_at, updated_at, completed_at FROM media_assets WHERE id = \$1 AND deleted_at IS NULL`).
		WithArgs("media_e2e_123").
		WillReturnRows(sqlmock.NewRows([]string{"id", "owner_id", "object_key", "original_name", "mime_type", "width", "height", "size", "sha256", "status", "created_at", "updated_at", "completed_at"}).
			AddRow("media_e2e_123", testUser.ID, objectKey, "photo.jpg", "image/jpeg", 2400, 1600, rawSize, rawHash, "pending", time.Now(), time.Now(), nil))

	// Begin complete tx
	mock.ExpectBegin()
	mock.ExpectExec(`UPDATE media_assets SET status = 'ready'`).
		WithArgs(2400, 1600, sqlmock.AnyArg(), "media_e2e_123", testUser.ID).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Enqueue outbox media.process
	mock.ExpectExec(`INSERT INTO outbox_events`).
		WithArgs(sqlmock.AnyArg(), "media.process", "media", "media_e2e_123", sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	completeReqBody, _ := json.Marshal(map[string]any{
		"size":   rawSize,
		"sha256": rawHash,
	})
	completeReq := httptest.NewRequest(http.MethodPost, "/api/v1/media/media_e2e_123/complete", bytes.NewReader(completeReqBody))
	completeReq.Header.Set("Authorization", "Bearer valid_token")
	completeRec := httptest.NewRecorder()

	handler.ServeHTTP(completeRec, completeReq)
	if completeRec.Code != http.StatusOK {
		t.Fatalf("completeMedia returned status %d: %s", completeRec.Code, completeRec.Body.String())
	}

	// Step 3: Outbox MediaHandler 执行真实的 media.process
	mediaHandler := outbox.MediaHandler{
		DB:      db,
		Storage: store,
	}

	// 幂等性检查
	mock.ExpectQuery(`SELECT COUNT\(\*\) FROM media_variants WHERE media_id = \$1 AND status = 'ready'`).
		WithArgs("media_e2e_123").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))

	// 变体写入 DB
	mock.ExpectBegin()
	mock.ExpectExec(`INSERT INTO media_variants .* VALUES \(\$1, 'source'`).
		WithArgs("media_e2e_123", objectKey, "image/jpeg", 2400, 1600, rawSize, rawHash, sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`INSERT INTO media_variants .* VALUES \(\$1, 'original'`).
		WithArgs("media_e2e_123", objectKey+"_original.jpg", 2400, 1600, sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`INSERT INTO media_variants .* VALUES \(\$1, 'detail'`).
		WithArgs("media_e2e_123", objectKey+"_detail.jpg", 1440, 960, sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`INSERT INTO media_variants .* VALUES \(\$1, 'thumb'`).
		WithArgs("media_e2e_123", objectKey+"_thumb.jpg", 640, 427, sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	procPayload, _ := json.Marshal(outbox.MediaProcessPayload{
		MediaID:   "media_e2e_123",
		ObjectKey: objectKey,
		MimeType:  "image/jpeg",
		Width:     2400,
		Height:    1600,
		SizeBytes: rawSize,
		SHA256:    rawHash,
	})

	if err := mediaHandler.Handle(context.Background(), outbox.Event{
		EventType: "media.process",
		Payload:   procPayload,
	}); err != nil {
		t.Fatalf("MediaHandler.Handle media.process failed: %v", err)
	}

	// 真实验证对象存储中的三个物理文件生成
	origBytes, okOrig := store.GetBytes(objectKey + "_original.jpg")
	detailBytes, okDetail := store.GetBytes(objectKey + "_detail.jpg")
	thumbBytes, okThumb := store.GetBytes(objectKey + "_thumb.jpg")
	if !okOrig || !okDetail || !okThumb {
		t.Fatalf("storage missing generated variants: orig=%v, detail=%v, thumb=%v", okOrig, okDetail, okThumb)
	}

	// 验证体积递进关系
	if !(len(thumbBytes) < len(detailBytes) && len(detailBytes) < len(origBytes)) {
		t.Errorf("byte size progression violated: thumb=%d, detail=%d, orig=%d", len(thumbBytes), len(detailBytes), len(origBytes))
	}

	// Step 4: 验证帖子详情富化输出 (enrichPostResponse)
	mockServer := &Server{db: db}
	postResp := &postResponse{
		ID:     "post-1",
		Author: userSummary{ID: testUser.ID, Username: testUser.Username},
	}

	// Query post_media
	mock.ExpectQuery(`SELECT ma\.id, ma\.mime_type, ma\.width, ma\.height, ma\.original_name, ma\.object_key FROM post_media pm JOIN media_assets ma`).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "mime_type", "width", "height", "original_name", "object_key"}).
			AddRow("media_e2e_123", "image/jpeg", 2400, 1600, "photo.jpg", objectKey))

	// Query media_variants
	mock.ExpectQuery(`SELECT mv\.media_id, mv\.variant, mv\.object_key, mv\.mime_type, mv\.width, mv\.height, mv\.size_bytes FROM media_variants mv`).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{"media_id", "variant", "object_key", "mime_type", "width", "height", "size_bytes"}).
			AddRow("media_e2e_123", "thumb", objectKey+"_thumb.jpg", "image/jpeg", 640, 427, int64(len(thumbBytes))).
			AddRow("media_e2e_123", "detail", objectKey+"_detail.jpg", "image/jpeg", 1440, 960, int64(len(detailBytes))).
			AddRow("media_e2e_123", "original", objectKey+"_original.jpg", "image/jpeg", 2400, 1600, int64(len(origBytes))))

	// Query user profile level
	mock.ExpectQuery(`SELECT CASE WHEN u\.account_type = 'guest' THEN 0 ELSE COALESCE\(up\.level, 1\) END`).
		WithArgs(testUser.ID).
		WillReturnRows(sqlmock.NewRows([]string{"level"}).AddRow(1))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/posts/post-1?include_details=1", nil)
	if err := mockServer.enrichPostResponse(context.Background(), req, postResp, false); err != nil {
		t.Fatalf("enrichPostResponse failed: %v", err)
	}

	if len(postResp.Media) != 1 {
		t.Fatalf("expected 1 media item, got %d", len(postResp.Media))
	}
	m := postResp.Media[0]
	if m.Thumb == nil || m.Detail == nil || m.Original == nil {
		t.Fatalf("postMediaResponse missing multi-level variants: thumb=%v, detail=%v, original=%v", m.Thumb, m.Detail, m.Original)
	}

	// 严格断言返回的变体尺寸与属性
	if m.Thumb.Width != 640 || m.Thumb.Height != 427 {
		t.Errorf("expected thumb 640x427, got %dx%d", m.Thumb.Width, m.Thumb.Height)
	}
	if m.Detail.Width != 1440 || m.Detail.Height != 960 {
		t.Errorf("expected detail 1440x960, got %dx%d", m.Detail.Width, m.Detail.Height)
	}
	if m.Original.Width != 2400 || m.Original.Height != 1600 {
		t.Errorf("expected original 2400x1600, got %dx%d", m.Original.Width, m.Original.Height)
	}

	t.Logf("====== E2E Media Pipeline Verification Results ======")
	t.Logf("Source Raw: 2400x1600, Size: %d Bytes, SHA256: %s", rawSize, rawHash)
	t.Logf("Thumb:      %dx%d, Size: %d Bytes, URL: %s", m.Thumb.Width, m.Thumb.Height, m.Thumb.SizeBytes, m.Thumb.URL)
	t.Logf("Detail:     %dx%d, Size: %d Bytes, URL: %s", m.Detail.Width, m.Detail.Height, m.Detail.SizeBytes, m.Detail.URL)
	t.Logf("Original:   %dx%d, Size: %d Bytes, URL: %s", m.Original.Width, m.Original.Height, m.Original.SizeBytes, m.Original.URL)

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet sqlmock expectations: %v", err)
	}
}
