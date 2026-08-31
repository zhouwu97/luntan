package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestGetUserProfileReturnsRegisteredPublicID(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, COALESCE\(u\.public_id::text, ''\), u\.username`).
		WithArgs("u1", "").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "public_id", "username", "nickname", "avatar_media_id",
			"avatar_object_key", "background_media_id", "background_object_key", "bio", "level",
			"trust_level", "status", "created_at", "experience", "account_type",
			"post_count", "comment_count", "follower_count", "following_count",
		}).AddRow(
			"u1", "10000", "cup_master", "杯友老张", "",
			"avatars/u1.webp", "", "", "评测老手",
			1, "new", "active", time.Date(2026, 8, 30, 0, 0, 0, 0, time.UTC),
			0, "email", 0, 7, 0, 0,
		))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/users/u1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", res.Code, res.Body.String())
	}
	body := res.Body.String()
	if body == "" || !strings.Contains(body, `"public_id":"10000"`) {
		t.Fatalf("public_id missing from response: %s", body)
	}
	if !strings.Contains(body, `"avatar_url":`) || !strings.Contains(body, `"comment_count":0`) {
		t.Fatalf("avatar_url or comment_count missing from response: %s", body)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestListUserCommentsForbiddenForOtherUsers(t *testing.T) {
	db, _, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	req := httptest.NewRequest(http.MethodGet, "/api/v1/users/u1/comments", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusForbidden {
		t.Fatalf("expected 403 FORBIDDEN, got status=%d body=%s", res.Code, res.Body.String())
	}
	if !strings.Contains(res.Body.String(), "FORBIDDEN") {
		t.Fatalf("expected FORBIDDEN code, got body=%s", res.Body.String())
	}
}
