package api

import (
	"database/sql"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestAPIWithoutDatabaseReturns503(t *testing.T) {
	for _, path := range []string{"/api/v1/community-categories", "/api/v1/communities", "/api/v1/feed/latest", "/api/v1/posts/p1", "/api/v1/auth/register", "/api/v1/auth/login", "/api/v1/auth/refresh", "/api/v1/auth/logout", "/api/v1/me"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		if strings.Contains(path, "/auth/") {
			req = httptest.NewRequest(http.MethodPost, path, strings.NewReader(`{"username":"user","password":"password123"}`))
		}
		res := httptest.NewRecorder()
		NewHandler(nil).ServeHTTP(res, req)
		if res.Code != http.StatusServiceUnavailable {
			t.Fatalf("%s status = %d, want 503", path, res.Code)
		}
	}
}

func TestAuthMethodAndBearerValidation(t *testing.T) {
	db, _, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	methodReq := httptest.NewRequest(http.MethodGet, "/api/v1/auth/register", nil)
	methodRes := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(methodRes, methodReq)
	if methodRes.Code != http.StatusMethodNotAllowed {
		t.Fatalf("auth method status = %d, want 405", methodRes.Code)
	}

	meReq := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	meRes := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(meRes, meReq)
	if meRes.Code != http.StatusUnauthorized || !strings.Contains(meRes.Body.String(), `"code":"INVALID_TOKEN"`) {
		t.Fatalf("missing bearer response: status=%d body=%s", meRes.Code, meRes.Body.String())
	}
}

func TestRegisterRejectsWeakPasswordBeforeDatabaseAccess(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", strings.NewReader(`{"username":"new_user","password":"short"}`))
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusBadRequest || !strings.Contains(res.Body.String(), `"code":"INVALID_INPUT"`) {
		t.Fatalf("weak password response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestListCommunities(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(`(?s)SELECT id, category_id.*FROM communities`).WithArgs("category-campus", "active").WillReturnRows(sqlmock.NewRows([]string{"id", "category_id", "slug", "name", "description", "avatar", "banner", "visibility", "join_policy", "status", "member_count", "follower_count", "post_count", "sort_order"}).AddRow("c1", "cat1", "campus", "校园", "交流", "", "", "public", "open", "active", 1, 2, 3, 1))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/communities?category_id=category-campus&status=active", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"id":"c1"`) {
		t.Fatalf("communities response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestLatestFeedUsesStableCursorAndReturnsNextCursor(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	created := time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{"id", "author_id", "username", "nickname", "community_id", "slug", "community_name", "type", "title", "content", "comment_count", "like_count", "bookmark_count", "share_count", "view_count", "created_at", "updated_at", "published_at"}).
		AddRow("p2", "u1", "user", "用户", "c1", "campus", "校园", "normal", "第二条", "正文", 2, 3, 0, 0, 5, created, created, created).
		AddRow("p1", "u1", "user", "用户", "c1", "campus", "校园", "normal", "第一条", "正文", 1, 2, 0, 0, 4, created.Add(-time.Minute), created.Add(-time.Minute), created.Add(-time.Minute))
	mock.ExpectQuery(`(?s)SELECT p.id, p.author_id.*ORDER BY p.published_at DESC, p.id DESC LIMIT \$1`).WithArgs(2).WillReturnRows(rows)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/feed/latest?limit=1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"has_more":true`) || !strings.Contains(res.Body.String(), `"next_cursor":"`) {
		t.Fatalf("feed response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestGetPostHidesModeratedRows(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	created := time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{"id", "author_id", "username", "nickname", "community_id", "slug", "community_name", "type", "title", "content", "comment_count", "like_count", "bookmark_count", "share_count", "view_count", "created_at", "updated_at", "published_at", "publication_status", "moderation_status", "deleted_at"}).AddRow("p1", "u1", "user", "用户", "c1", "campus", "校园", "normal", "标题", "正文", 0, 0, 0, 0, 1, created, created, created, "published", "hidden", nil)
	mock.ExpectQuery(`(?s)SELECT p.id, p.author_id.*WHERE p.id = \$1`).WithArgs("p1").WillReturnRows(rows)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/posts/p1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusNotFound {
		t.Fatalf("hidden post status = %d, want 404", res.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestAPIUsesDatabaseErrorsAsInternalError(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(regexp.QuoteMeta("SELECT id, category_id")).WillReturnError(sql.ErrConnDone)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/communities", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusInternalServerError || !strings.Contains(res.Body.String(), `"code":"INTERNAL_ERROR"`) {
		t.Fatalf("db error response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
