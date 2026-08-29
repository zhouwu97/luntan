package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestCapabilityMatrix(t *testing.T) {
	actions := []string{
		"can_publish",
		"can_comment",
		"can_like",
		"can_bookmark",
		"can_follow",
		"can_upload_media",
		"can_vote",
		"can_manage_profile",
		"can_manage_bookmarks",
		"can_create_poll",
		"can_report",
		"can_moderate",
		"can_manage_admins",
		"can_ban_ip",
	}
	allFalse := func() map[string]bool {
		caps := make(map[string]bool, len(actions))
		for _, action := range actions {
			caps[action] = false
		}
		return caps
	}
	rolePermissions := []string{"moderation.action", "report.review", "audit.read", "user.ban.global"}
	roles := []struct {
		name        string
		user        auth.User
		role        string
		permissions []string
		expect      map[string]bool
	}{
		{name: "anonymous", user: auth.User{}, expect: allFalse()},
		{
			name: "guest_user",
			user: auth.User{ID: "guest-1", AccountType: "guest"},
			expect: map[string]bool{
				"can_publish": false, "can_comment": true, "can_like": true,
				"can_bookmark": false, "can_follow": false, "can_upload_media": false,
				"can_vote": false, "can_manage_profile": false,
				"can_manage_bookmarks": false, "can_create_poll": false,
				"can_report": true, "can_moderate": false,
				"can_manage_admins": false, "can_ban_ip": false,
			},
		},
		{
			name: "normal_user",
			user: auth.User{ID: "user-1", AccountType: "email"},
			expect: map[string]bool{
				"can_publish": true, "can_comment": true, "can_like": true,
				"can_bookmark": true, "can_follow": true, "can_upload_media": true,
				"can_vote": true, "can_manage_profile": true,
				"can_manage_bookmarks": true, "can_create_poll": true,
				"can_report": true, "can_moderate": false,
				"can_manage_admins": false, "can_ban_ip": false,
			},
		},
		{
			name:        "admin",
			user:        auth.User{ID: "admin-1", AccountType: "email"},
			role:        "platform_admin",
			permissions: rolePermissions,
			expect: map[string]bool{
				"can_publish": true, "can_comment": true, "can_like": true,
				"can_bookmark": true, "can_follow": true, "can_upload_media": true,
				"can_vote": true, "can_manage_profile": true,
				"can_manage_bookmarks": true, "can_create_poll": true,
				"can_report": true, "can_moderate": true,
				"can_manage_admins": false, "can_ban_ip": false,
			},
		},
		{
			name:        "super_admin",
			user:        auth.User{ID: "super-1", AccountType: "email"},
			role:        "super_admin",
			permissions: rolePermissions,
			expect: map[string]bool{
				"can_publish": true, "can_comment": true, "can_like": true,
				"can_bookmark": true, "can_follow": true, "can_upload_media": true,
				"can_vote": true, "can_manage_profile": true,
				"can_manage_bookmarks": true, "can_create_poll": true,
				"can_report": true, "can_moderate": true,
				"can_manage_admins": true, "can_ban_ip": true,
			},
		},
	}

	for _, role := range roles {
		t.Run(role.name, func(t *testing.T) {
			caps := capabilitiesForUser(role.user)
			for _, permission := range role.permissions {
				applyPermissionCapability(caps, role.role, permission)
			}
			for _, action := range actions {
				if got, want := caps[action], role.expect[action]; got != want {
					t.Errorf("%s: %s=%v，期望=%v", role.name, action, got, want)
				}
			}
		})
	}
}

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

func TestActiveMuteRemovesCommentCapabilityAndExposesExpiry(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	until := time.Now().UTC().Add(24 * time.Hour).Truncate(time.Microsecond)
	mock.ExpectQuery(`(?s)SELECT ends_at.*FROM restrictions`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"ends_at"}).AddRow(until))

	server := &Server{db: db}
	user := auth.User{ID: "user-1", AccountType: "email"}
	caps := capabilitiesForUser(user)
	if err := server.applyActiveMute(context.Background(), &user, caps); err != nil {
		t.Fatal(err)
	}
	if caps[capComment] {
		t.Fatal("active mute must disable comment capability")
	}
	if !user.CommentRestricted || user.CommentRestrictedUntil == nil {
		t.Fatal("active mute expiry should be exposed on user state")
	}
	if !user.CommentRestrictedUntil.Equal(until) {
		t.Fatalf("mute expiry = %v, want %v", user.CommentRestrictedUntil, until)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
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
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).
			AddRow("guest-1", "guest_1", "active", "游客", 0, 0, "guest", "", false, nil, false))

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
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).
			AddRow("guest-1", "guest_1", "active", "游客", 0, 0, "guest", "", false, nil, false))

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
