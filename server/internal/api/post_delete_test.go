package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestAdminCanDeleteAnotherUsersPost(t *testing.T) {
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
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id FROM posts WHERE id = $1 FOR UPDATE`)).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{"author_id"}).AddRow("author-1"))
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE posts SET post_status = 'deleted', deleted_at = COALESCE(deleted_at, now()), publication_status = 'deleted', deleted_by = NULLIF($2, ''), delete_reason = $3, updated_at = now() WHERE id = $1`)).
		WithArgs("post-1", "admin-1", "管理员手动删除帖子").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/posts/post-1", strings.NewReader(`{}`))
	req.Header.Set("Authorization", "Bearer admin-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNoContent {
		t.Fatalf("admin delete status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestRegularUserCannotDeleteAnotherUsersPost(t *testing.T) {
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
		}).AddRow("user-1", "user", "active", "用户", 1, 0, "email", "", false, nil, false))
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id FROM posts WHERE id = $1 FOR UPDATE`)).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{"author_id"}).AddRow("author-1"))
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("user-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))
	mock.ExpectRollback()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/posts/post-1", strings.NewReader(`{}`))
	req.Header.Set("Authorization", "Bearer user-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusForbidden {
		t.Fatalf("regular user delete status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestAdminPostViewerStateAllowsDelete(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT ma\.id, ma\.mime_type.*FROM post_media pm`).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "mime_type", "width", "height", "original_name", "object_key", "moderation_status", "mask_regions",
		}))
	mock.ExpectQuery(`(?s)SELECT COALESCE\(hot_suppressed, false\).*FROM posts WHERE id = \$1`).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"hot_suppressed", "hot_suppressed_reason", "hot_suppressed_at", "hot_suppressed_by",
		}).AddRow(false, "", nil, ""))
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))
	mock.ExpectQuery(`(?s)SELECT CASE WHEN u\.account_type = 'guest'.*FROM users u`).
		WithArgs("author-1").
		WillReturnRows(sqlmock.NewRows([]string{"level", "avatar_media_id", "object_key"}).AddRow(1, "", ""))
	mock.ExpectQuery(`(?s)SELECT\s+EXISTS \(SELECT 1 FROM post_reactions`).
		WithArgs("post-1", "admin-1", "author-1", "community-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"has_liked", "has_bookmarked", "is_following_author", "is_following_community", "is_community_member",
		}).AddRow(false, false, false, false, false))

	server := &Server{db: db}
	post := &postResponse{
		ID:     "post-1",
		Author: userSummary{ID: "author-1"},
		Community: communitySummary{
			ID: "community-1",
		},
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/posts/post-1?include_details=1", nil)
	req = req.WithContext(context.WithValue(req.Context(), authenticatedUserContextKey{}, auth.User{
		ID:          "admin-1",
		AccountType: "email",
	}))

	if err := server.enrichPostResponse(req.Context(), req, post, true); err != nil {
		t.Fatalf("enrichPostResponse error: %v", err)
	}
	if post.ViewerState == nil || !post.ViewerState.CanDelete {
		t.Fatalf("admin viewer state should allow delete, got %+v", post.ViewerState)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}
