package api

import (
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestDeleteRankingToyCommentRequiresAuth(t *testing.T) {
	db, _, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ranking/toy-comments/c-1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", res.Code)
	}
}

func TestDeleteRankingToyCommentRequiresPermission(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("user-1", "user", "active", "普通用户", 1, 0, "email", "", false, nil, false))

	// canModerate check
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("user-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))
	// admin.role.manage check
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("user-1", "admin.role.manage").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ranking/toy-comments/c-1", nil)
	req.Header.Set("Authorization", "Bearer user-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestDeleteRankingToyCommentRootSuccess(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("admin-1", "admin", "active", "管理员", 1, 0, "email", "", false, nil, false))

	// canModerate check -> true
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	mock.ExpectBegin()
	// Lock comment (root comment, root_id == id, parent_id == nil)
	mock.ExpectQuery(`(?s)SELECT toy_id, COALESCE\(root_id, id\), parent_id, deleted_at FROM ranking_toy_comments WHERE id = \$1 FOR UPDATE`).
		WithArgs("root-1").
		WillReturnRows(sqlmock.NewRows([]string{"toy_id", "root_id", "parent_id", "deleted_at"}).
			AddRow("toy-1", "root-1", nil, nil))

	// Soft delete root comment and all replies in thread
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE ranking_toy_comments SET deleted_at = now(), updated_at = now() WHERE (id = $1 OR root_id = $1) AND deleted_at IS NULL`)).
		WithArgs("root-1").
		WillReturnResult(sqlmock.NewResult(1, 2))

	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ranking/toy-comments/root-1", nil)
	req.Header.Set("Authorization", "Bearer admin-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestDeleteRankingToyCommentReplyDecrementsReplyCount(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("admin-1", "admin", "active", "管理员", 1, 0, "email", "", false, nil, false))

	// canModerate check -> true
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	mock.ExpectBegin()
	// Lock comment (reply, root_id == "root-1", parent_id == "root-1")
	mock.ExpectQuery(`(?s)SELECT toy_id, COALESCE\(root_id, id\), parent_id, deleted_at FROM ranking_toy_comments WHERE id = \$1 FOR UPDATE`).
		WithArgs("reply-1").
		WillReturnRows(sqlmock.NewRows([]string{"toy_id", "root_id", "parent_id", "deleted_at"}).
			AddRow("toy-1", "root-1", "root-1", nil))

	// Soft delete reply
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE ranking_toy_comments SET deleted_at = now(), updated_at = now() WHERE id = $1 AND deleted_at IS NULL`)).
		WithArgs("reply-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Decrement root comment's reply_count
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE ranking_toy_comments SET reply_count = GREATEST(reply_count - 1, 0), updated_at = now() WHERE id = $1`)).
		WithArgs("root-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ranking/toy-comments/reply-1", nil)
	req.Header.Set("Authorization", "Bearer admin-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestDeleteRankingToyCommentRepeatedDeleteDoesNotDoubleDecrement(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("admin-1", "admin", "active", "管理员", 1, 0, "email", "", false, nil, false))

	// canModerate check -> true
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	mock.ExpectBegin()
	// Lock comment where deleted_at is already set (already deleted)
	mock.ExpectQuery(`(?s)SELECT toy_id, COALESCE\(root_id, id\), parent_id, deleted_at FROM ranking_toy_comments WHERE id = \$1 FOR UPDATE`).
		WithArgs("reply-already-deleted").
		WillReturnRows(sqlmock.NewRows([]string{"toy_id", "root_id", "parent_id", "deleted_at"}).
			AddRow("toy-1", "root-1", "root-1", time.Now()))

	// No UPDATE executed, no reply_count decremented!
	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ranking/toy-comments/reply-already-deleted", nil)
	req.Header.Set("Authorization", "Bearer admin-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestDeleteRankingToyCommentNotFound(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("admin-1", "admin", "active", "管理员", 1, 0, "email", "", false, nil, false))

	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	mock.ExpectBegin()
	mock.ExpectQuery(`(?s)SELECT toy_id, COALESCE\(root_id, id\), parent_id, deleted_at FROM ranking_toy_comments WHERE id = \$1 FOR UPDATE`).
		WithArgs("nonexistent").
		WillReturnRows(sqlmock.NewRows([]string{"toy_id", "root_id", "parent_id", "deleted_at"}))
	mock.ExpectRollback()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/ranking/toy-comments/nonexistent", nil)
	req.Header.Set("Authorization", "Bearer admin-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}
