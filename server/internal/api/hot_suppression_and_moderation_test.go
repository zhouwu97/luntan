package api

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestSetPostHotSuppressionRequiresAdmin(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// Anonymous user -> 401
	req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/posts/post-101/hot-suppression", strings.NewReader(`{"suppressed":true,"reason":"不适合热门"}`))
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 Unauthorized, got status=%d", res.Code)
	}

	// Normal user (no capModerate) -> 403
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).
			AddRow("u1", "normal_user", "active", "普通用户", 1, 0, "email", "", false, nil, false))
	// Global permission check
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("u1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	req = httptest.NewRequest(http.MethodPut, "/api/v1/admin/posts/post-101/hot-suppression", strings.NewReader(`{"suppressed":true,"reason":"不适合热门"}`))
	req.Header.Set("Authorization", "Bearer access-token-normal")
	res = httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for non-admin, got status=%d", res.Code)
	}
}

func TestSetPostHotSuppressionSuccessForAdmin(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).
			AddRow("admin_1", "admin_user", "active", "管理员", 1, 0, "email", "", false, nil, false))
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin_1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	mock.ExpectQuery(`(?s)SELECT EXISTS \(SELECT 1 FROM posts WHERE id = \$1 AND deleted_at IS NULL\)`).
		WithArgs("post-101").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	// BeginTx for hot suppression and admin log
	mock.ExpectBegin()
	mock.ExpectExec(`(?s)UPDATE posts.*SET hot_suppressed = true.*WHERE id = \$4`).
		WithArgs("admin_1", sqlmock.AnyArg(), "不适合作为热门内容展示", "post-101").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Admin log inside same tx
	mock.ExpectQuery(`(?s)SELECT last_hash FROM admin_log_chain`).
		WillReturnRows(sqlmock.NewRows([]string{"last_hash"}).AddRow("genesis_hash"))
	mock.ExpectExec(`(?s)INSERT INTO admin_logs`).
		WithArgs(sqlmock.AnyArg(), "admin_1", "post.hot_suppression", "post", "post-101", "", sqlmock.AnyArg(), "genesis_hash", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`(?s)UPDATE admin_log_chain SET last_hash = \$1 WHERE id = 1`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/posts/post-101/hot-suppression", strings.NewReader(`{"suppressed":true,"reason":"不适合作为热门内容展示"}`))
	req.Header.Set("Authorization", "Bearer access-token-admin")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got status=%d body=%s", res.Code, res.Body.String())
	}
	if !strings.Contains(res.Body.String(), `"hot_suppressed":true`) {
		t.Fatalf("expected hot_suppressed true in response, got %s", res.Body.String())
	}
}

func TestModerateMediaRejectsVideo(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).
			AddRow("admin_1", "admin_user", "active", "管理员", 1, 0, "email", "", false, nil, false))
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin_1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	mock.ExpectQuery(`(?s)SELECT object_key, mime_type, status FROM media_assets WHERE id = \$1 AND deleted_at IS NULL`).
		WithArgs("media_video_1").
		WillReturnRows(sqlmock.NewRows([]string{"object_key", "mime_type", "status"}).AddRow("media/u1/video.mp4", "video/mp4", "ready"))

	payload := `{"moderation_status":"censored","mask_regions":[{"x":0.2,"y":0.3,"width":0.4,"height":0.3,"type":"mosaic"}],"reason":"视频打码测试"}`
	req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/media/media_video_1/moderation", bytes.NewReader([]byte(payload)))
	req.Header.Set("Authorization", "Bearer access-token-admin")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request for video moderation, got status=%d body=%s", res.Code, res.Body.String())
	}
	if !strings.Contains(res.Body.String(), "MEDIA_NOT_IMAGE") {
		t.Fatalf("expected MEDIA_NOT_IMAGE error code, got %s", res.Body.String())
	}
}

func TestModerateMediaNormalReset(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).
			AddRow("admin_1", "admin_user", "active", "管理员", 1, 0, "email", "", false, nil, false))
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin_1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	mock.ExpectQuery(`(?s)SELECT object_key, mime_type, status FROM media_assets WHERE id = \$1 AND deleted_at IS NULL`).
		WithArgs("media_101").
		WillReturnRows(sqlmock.NewRows([]string{"object_key", "mime_type", "status"}).AddRow("media/u1/media_101", "image/jpeg", "ready"))

	mock.ExpectBegin()
	mock.ExpectExec(`(?s)UPDATE media_assets.*SET moderation_status = 'normal'.*WHERE id = \$4`).
		WithArgs("admin_1", sqlmock.AnyArg(), "恢复原图展示", "media_101").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Admin log
	mock.ExpectQuery(`(?s)SELECT last_hash FROM admin_log_chain`).
		WillReturnRows(sqlmock.NewRows([]string{"last_hash"}).AddRow("genesis_hash"))
	mock.ExpectExec(`(?s)INSERT INTO admin_logs`).
		WithArgs(sqlmock.AnyArg(), "admin_1", "media.moderation", "media", "media_101", "", sqlmock.AnyArg(), "genesis_hash", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`(?s)UPDATE admin_log_chain SET last_hash = \$1 WHERE id = 1`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	payload := `{"moderation_status":"normal","reason":"恢复原图展示"}`
	req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/media/media_101/moderation", bytes.NewReader([]byte(payload)))
	req.Header.Set("Authorization", "Bearer access-token-admin")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got status=%d body=%s", res.Code, res.Body.String())
	}
	if !strings.Contains(res.Body.String(), `"moderation_status":"normal"`) {
		t.Fatalf("expected moderation_status normal in response, got %s", res.Body.String())
	}
}

func TestDirectRawMediaBlockedWhenCensored(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// Anonymous / normal user requests raw image that is censored
	mock.ExpectQuery(`(?s)SELECT EXISTS.*FROM media_assets.*WHERE object_key = \$1 AND moderation_status = 'censored'`).
		WithArgs("media/u1/sensitive.jpg").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/media-file/media/u1/sensitive.jpg", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden when requesting raw censored media, got status=%d", res.Code)
	}
}

func TestEnrichPostHotSuppressionHiddenFromNonAdmin(t *testing.T) {
	s := &Server{}
	resp := postResponse{
		ID: "post-101",
	}

	// For regular user, hot suppression metadata is sanitized
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	s.db = db

	mock.ExpectQuery(`(?s)SELECT COALESCE\(ma\.id, ''\), COALESCE\(ma\.object_key, ''\).*FROM post_media pm`).
		WithArgs("post-101").
		WillReturnRows(sqlmock.NewRows([]string{"id", "object_key", "mime_type", "width", "height", "size_bytes", "sha256", "created_at", "moderation_status"}))

	mock.ExpectQuery(`(?s)SELECT COALESCE\(hot_suppressed, false\), COALESCE\(hot_suppressed_reason, ''\), hot_suppressed_at, COALESCE\(hot_suppressed_by, ''\) FROM posts WHERE id = \$1`).
		WithArgs("post-101").
		WillReturnRows(sqlmock.NewRows([]string{"hot_suppressed", "hot_suppressed_reason", "hot_suppressed_at", "hot_suppressed_by"}).
			AddRow(true, "敏感内容移出热门", nil, "admin-1"))

	mock.ExpectQuery(`(?s)SELECT CASE WHEN u\.account_type = 'guest' THEN 0 ELSE COALESCE\(up\.level, 1\) END.*FROM users u`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"level", "avatar_media_id", "object_key"}).AddRow(1, "", ""))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/posts/post-101", nil)
	_ = s.enrichPostResponse(req.Context(), req, &resp, false)

	if resp.HotSuppressed {
		t.Fatalf("expected HotSuppressed to be false for non-admin viewer, got %v", resp.HotSuppressed)
	}
	if resp.HotSuppressedReason != "" {
		t.Fatalf("expected HotSuppressedReason to be empty for non-admin viewer, got %s", resp.HotSuppressedReason)
	}
}

func TestCreateActivityPostRequiresAdmin(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// Normal user (no moderation permission)
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).
			AddRow("user_1", "regular_user", "active", "普通用户", 1, 0, "email", "", false, nil, false))
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("user_1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	payload := `{"community_id":"community-campus","type":"activity","title":"普通用户尝试发布活动","content":"正文"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts", bytes.NewReader([]byte(payload)))
	req.Header.Set("Authorization", "Bearer access-token-normal")
	req.Header.Set("Idempotency-Key", "idem-act-101")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden when normal user creates activity post, got %d body=%s", res.Code, res.Body.String())
	}
}
