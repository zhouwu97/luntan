package api

import (
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestNotificationCategoryValidation(t *testing.T) {
	for _, value := range []string{"", "all", "reply", "like", "system"} {
		category, err := parseNotificationCategory(value)
		if err != nil {
			t.Fatalf("parseNotificationCategory(%q): %v", value, err)
		}
		if value == "" && category != "all" {
			t.Fatalf("empty category = %q, want all", category)
		}
	}
	if _, err := parseNotificationCategory("unknown"); err == nil {
		t.Fatal("unknown category should be rejected")
	}
}

func TestNotificationCursorIsBoundToCategory(t *testing.T) {
	encoded, err := encodeNotificationCursor(notificationCursor{
		CreatedAt: time.Date(2026, 8, 24, 10, 0, 0, 0, time.UTC),
		ID:        "notification-1",
		Category:  "reply",
	})
	if err != nil {
		t.Fatal(err)
	}
	cursor, err := decodeNotificationCursor(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if cursor.Category != "reply" {
		t.Fatalf("cursor category = %q, want reply", cursor.Category)
	}
	if cursor.Category == "like" {
		t.Fatal("reply cursor must not be reusable for like category")
	}
}

func TestUnreadNotificationCountUsesAuthenticatedUserID(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).AddRow("user-a", "a", "active", "A", 1, 0, "email", "", false, nil, false))
	mock.ExpectQuery(`(?s)SELECT count\(\*\) FROM notifications n WHERE n\.user_id = \$1 AND n\.is_read = false.*FROM blocks b`).
		WithArgs("user-a").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(int64(3)))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/notifications/unread-count", nil)
	req.Header.Set("Authorization", "Bearer access-a")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"unread_count":3`) {
		t.Fatalf("unread count response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestMarkNotificationReadUsesPatchReadRouteAndRejectsOtherUsers(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).AddRow("user-a", "a", "active", "A", 1, 0, "email", "", false, nil, false))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE notifications SET is_read = true, read_at = COALESCE(read_at, now()) WHERE id = $1 AND user_id = $2`)).
		WithArgs("notification-b", "user-a").
		WillReturnResult(sqlmock.NewResult(0, 0))

	req := httptest.NewRequest(http.MethodPatch, "/api/v1/notifications/notification-b/read", nil)
	req.Header.Set("Authorization", "Bearer access-a")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNotFound || !strings.Contains(res.Body.String(), `"code":"NOTIFICATION_NOT_FOUND"`) {
		t.Fatalf("missing notification response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestNotificationReadRouteDoesNotAcceptLegacyPath(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/notifications/n1/read", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusMethodNotAllowed {
		t.Fatalf("legacy notification route status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestMarkNotificationReadUpdatesRows(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).AddRow("user-a", "a", "active", "A", 1, 0, "email", "", false, nil, false))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE notifications SET is_read = true, read_at = COALESCE(read_at, now()) WHERE id = $1 AND user_id = $2`)).
		WithArgs("notification-a", "user-a").
		WillReturnResult(sqlmock.NewResult(0, 1))

	req := httptest.NewRequest(http.MethodPatch, "/api/v1/notifications/notification-a/read", nil)
	req.Header.Set("Authorization", "Bearer access-a")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"is_read":true`) {
		t.Fatalf("read response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
