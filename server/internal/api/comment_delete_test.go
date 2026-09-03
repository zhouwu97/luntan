package api

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestRegularUserCanDeleteOwnComment(t *testing.T) {
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
		}).AddRow("user-author", "user", "active", "普通作者", 1, 0, "email", "", false, nil, false))

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id, deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-1").
		WillReturnRows(sqlmock.NewRows([]string{"author_id", "deleted_at"}).AddRow("user-author", nil))

	// softDeleteCommentTx
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id, COALESCE(root_id, id), deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-1").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "deleted_at"}).AddRow("post-1", "comment-1", nil))

	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comments SET deleted_at = now(), publication_status = 'deleted', deleted_by = NULLIF($2, ''), delete_reason = $3, moderation_case_id = NULLIF($4, ''), updated_at = now() WHERE id = $1 AND deleted_at IS NULL`)).
		WithArgs("comment-1", "user-author", "用户主动删除评论", "").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// decrement post comment count
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0), updated_at = now() WHERE id = $1`)).
		WithArgs("post-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/comment-1", nil)
	req.Header.Set("Authorization", "Bearer user-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestRegularUserCannotDeleteAnotherUsersComment(t *testing.T) {
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
		}).AddRow("other-user", "other", "active", "普通用户", 1, 0, "email", "", false, nil, false))

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id, deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-1").
		WillReturnRows(sqlmock.NewRows([]string{"author_id", "deleted_at"}).AddRow("author-1", nil))

	// canModerate check -> false
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("other-user", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	mock.ExpectRollback()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/comment-1", nil)
	req.Header.Set("Authorization", "Bearer other-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestAdminCanDeleteOwnComment(t *testing.T) {
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

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id, deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-own").
		WillReturnRows(sqlmock.NewRows([]string{"author_id", "deleted_at"}).AddRow("admin-1", nil))

	// softDeleteCommentTx: admin deleting own comment -> isAuthor is true
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id, COALESCE(root_id, id), deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-own").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "deleted_at"}).AddRow("post-1", "comment-own", nil))

	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comments SET deleted_at = now(), publication_status = 'deleted', deleted_by = NULLIF($2, ''), delete_reason = $3, moderation_case_id = NULLIF($4, ''), updated_at = now() WHERE id = $1 AND deleted_at IS NULL`)).
		WithArgs("comment-own", "admin-1", "用户主动删除评论", "").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// decrement post comment count
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0), updated_at = now() WHERE id = $1`)).
		WithArgs("post-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/comment-own", nil)
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

func TestAdminCanDeleteAnotherUsersComment(t *testing.T) {
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

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id, deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-other").
		WillReturnRows(sqlmock.NewRows([]string{"author_id", "deleted_at"}).AddRow("author-2", nil))

	// canModerate check -> true
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	// softDeleteCommentTx
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id, COALESCE(root_id, id), deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-other").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "deleted_at"}).AddRow("post-1", "comment-root", nil))

	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comments SET deleted_at = now(), publication_status = 'deleted', deleted_by = NULLIF($2, ''), delete_reason = $3, moderation_case_id = NULLIF($4, ''), updated_at = now() WHERE id = $1 AND deleted_at IS NULL`)).
		WithArgs("comment-other", "admin-1", "管理员手动删除评论", "").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// root_id != comment_id, decrement reply_count on root comment
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comments SET reply_count = GREATEST(reply_count - 1, 0), updated_at = now() WHERE id = $1`)).
		WithArgs("comment-root").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// decrement post comment count
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0), updated_at = now() WHERE id = $1`)).
		WithArgs("post-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/comment-other", nil)
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

func TestUnauthenticatedUserCannotDeleteComment(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/c-1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", res.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestCreateCommentRejectsOverNineMedia(t *testing.T) {
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
		}).AddRow("user-1", "user1", "active", "用户1", 1, 0, "email", "", false, nil, false))

	mock.ExpectQuery(`(?s)SELECT ends_at FROM restrictions WHERE user_id = \$1 AND restriction_type = 'mute'`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"ends_at"}))

	// 10 media IDs exceeds maximum of 9
	body := `{"content": "多图评论测试", "media_ids": ["m1","m2","m3","m4","m5","m6","m7","m8","m9","m10"]}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts/post-1/comments", bytes.NewBufferString(body))
	req.Header.Set("Authorization", "Bearer user-token")
	req.Header.Set("Content-Type", "application/json")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}
