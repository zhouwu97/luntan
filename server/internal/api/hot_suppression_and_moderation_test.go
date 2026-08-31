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

	mock.ExpectExec(`(?s)UPDATE posts.*SET hot_suppressed = true.*WHERE id = \$4`).
		WithArgs("admin_1", sqlmock.AnyArg(), "不适合作为热门内容展示", "post-101").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Admin log
	mock.ExpectBegin()
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

func TestModerateMediaMaskingSuccess(t *testing.T) {
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

	mock.ExpectExec(`(?s)UPDATE media_assets.*SET moderation_status = 'censored'.*WHERE id = \$5`).
		WithArgs(sqlmock.AnyArg(), "admin_1", sqlmock.AnyArg(), "敏感区域遮挡", "media_101").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Admin log
	mock.ExpectBegin()
	mock.ExpectQuery(`(?s)SELECT last_hash FROM admin_log_chain`).
		WillReturnRows(sqlmock.NewRows([]string{"last_hash"}).AddRow("genesis_hash"))
	mock.ExpectExec(`(?s)INSERT INTO admin_logs`).
		WithArgs(sqlmock.AnyArg(), "admin_1", "media.moderation", "media", "media_101", "", sqlmock.AnyArg(), "genesis_hash", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`(?s)UPDATE admin_log_chain SET last_hash = \$1 WHERE id = 1`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	payload := `{"moderation_status":"censored","mask_regions":[{"x":0.2,"y":0.3,"width":0.4,"height":0.3,"type":"mosaic"}],"reason":"敏感区域遮挡"}`
	req := httptest.NewRequest(http.MethodPut, "/api/v1/admin/media/media_101/moderation", bytes.NewReader([]byte(payload)))
	req.Header.Set("Authorization", "Bearer access-token-admin")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got status=%d body=%s", res.Code, res.Body.String())
	}
	if !strings.Contains(res.Body.String(), `"moderation_status":"censored"`) {
		t.Fatalf("expected moderation_status censored in response, got %s", res.Body.String())
	}
}
