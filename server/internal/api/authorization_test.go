package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestGuestCapabilitiesAllowParticipationButBlockPublishing(t *testing.T) {
	guest := capabilitiesForUser(auth.User{AccountType: "guest"})

	if guest["can_comment"] != true {
		t.Fatal("游客应当可以评论")
	}
	if guest["can_report"] != true {
		t.Fatal("游客应当可以举报")
	}
	if guest["can_publish"] != false {
		t.Fatal("游客不应当可以发帖")
	}
	if guest["can_create_poll"] != false {
		t.Fatal("游客不应当可以创建投票")
	}
	if guest["can_manage_bookmarks"] != false {
		t.Fatal("游客不应当可以管理收藏夹")
	}
}

func TestRegisteredCapabilitiesAllowPublishing(t *testing.T) {
	registered := capabilitiesForUser(auth.User{AccountType: "email"})

	if registered["can_publish"] != true || registered["can_create_poll"] != true {
		t.Fatal("正式账号应当可以发帖和创建投票")
	}
	if registered["can_manage_bookmarks"] != true {
		t.Fatal("正式账号应当可以管理收藏夹")
	}
}

func TestGuestCannotCreatePostThroughHTTPRoute(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "account_type", "email", "email_verified", "email_verified_at"}).
			AddRow("guest-1", "guest_1", "active", "游客", 1, "guest", "", false, nil))

	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts", strings.NewReader(`{"community_id":"c1","type":"normal","title":"标题","content":"正文"}`))
	req.Header.Set("Authorization", "Bearer guest-token")
	req.Header.Set("Idempotency-Key", "guest-post-1")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusForbidden || !strings.Contains(res.Body.String(), `"code":"REGISTERED_ACCOUNT_REQUIRED"`) {
		t.Fatalf("guest post status=%d body=%s expectations=%v", res.Code, res.Body.String(), mock.ExpectationsWereMet())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestGuestCannotManageBookmarkThroughHTTPRoute(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "account_type", "email", "email_verified", "email_verified_at"}).
			AddRow("guest-1", "guest_1", "active", "游客", 1, "guest", "", false, nil))

	req := httptest.NewRequest(http.MethodPut, "/api/v1/posts/p1/bookmark", nil)
	req.Header.Set("Authorization", "Bearer guest-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusForbidden || !strings.Contains(res.Body.String(), `"code":"REGISTERED_ACCOUNT_REQUIRED"`) {
		t.Fatalf("guest bookmark status=%d body=%s expectations=%v", res.Code, res.Body.String(), mock.ExpectationsWereMet())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
