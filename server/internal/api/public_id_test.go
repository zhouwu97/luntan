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
		WithArgs("u1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "public_id", "username", "nickname", "avatar_media_id",
			"background_media_id", "background_object_key", "bio", "level",
			"trust_level", "status", "created_at", "experience", "account_type",
			"post_count", "follower_count", "following_count",
		}).AddRow(
			"u1", "10000", "cup_master", "杯友老张", "", "", "", "评测老手",
			1, "new", "active", time.Date(2026, 8, 30, 0, 0, 0, 0, time.UTC),
			0, "email", 0, 0, 0,
		))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/users/u1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", res.Code, res.Body.String())
	}
	if body := res.Body.String(); body == "" || !strings.Contains(body, `"public_id":"10000"`) {
		t.Fatalf("public_id missing from response: %s", body)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
