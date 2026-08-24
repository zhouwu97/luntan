package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestNotificationsBelongToAuthenticatedUserAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	s.authService = auth.NewService(s.db)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	userA, err := s.authService.Register(context.Background(), auth.RegisterInput{
		Username: "notification_a_" + suffix,
		Password: "安全密码12345",
		Nickname: "通知用户 A",
	}, auth.SessionMetadata{UserAgent: "notification-integration", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	userB, err := s.authService.Register(context.Background(), auth.RegisterInput{
		Username: "notification_b_" + suffix,
		Password: "安全密码12345",
		Nickname: "通知用户 B",
	}, auth.SessionMetadata{UserAgent: "notification-integration", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, query := range []string{
			`DELETE FROM notifications WHERE user_id IN ($1, $2) OR actor_id IN ($1, $2)`,
			`DELETE FROM refresh_tokens WHERE user_id IN ($1, $2)`,
			`DELETE FROM sessions WHERE user_id IN ($1, $2)`,
			`DELETE FROM user_auth_methods WHERE user_id IN ($1, $2)`,
			`DELETE FROM user_profiles WHERE user_id IN ($1, $2)`,
			`DELETE FROM users WHERE id IN ($1, $2)`,
		} {
			if _, cleanupErr := s.db.Exec(query, userA.User.ID, userB.User.ID); cleanupErr != nil {
				t.Logf("notification fixture cleanup failed: %v", cleanupErr)
			}
		}
	})

	notificationIDs := make([]string, 0, 5)
	for index := 0; index < 3; index++ {
		id := "notification-a-" + suffix + fmt.Sprintf("-%d", index)
		notificationIDs = append(notificationIDs, id)
		if _, err := s.db.Exec(`INSERT INTO notifications (id, user_id, type, actor_id, target_type, target_id, is_read, created_at) VALUES ($1, $2, 'reply', $3, 'post', $4, false, $5)`, id, userA.User.ID, userB.User.ID, "post-a", time.Now().UTC()); err != nil {
			t.Fatal(err)
		}
	}
	for index := 0; index < 2; index++ {
		id := "notification-b-" + suffix + fmt.Sprintf("-%d", index)
		if _, err := s.db.Exec(`INSERT INTO notifications (id, user_id, type, actor_id, target_type, target_id, is_read, created_at) VALUES ($1, $2, 'reply', $3, 'post', $4, false, $5)`, id, userB.User.ID, userA.User.ID, "post-b", time.Now().UTC()); err != nil {
			t.Fatal(err)
		}
	}

	count := func(token string) int64 {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/notifications/unread-count", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		res := httptest.NewRecorder()
		s.ServeHTTP(res, req)
		if res.Code != http.StatusOK {
			t.Fatalf("unread count status=%d body=%s", res.Code, res.Body.String())
		}
		var payload struct {
			Count int64 `json:"unread_count"`
		}
		if err := json.Unmarshal(res.Body.Bytes(), &payload); err != nil {
			t.Fatal(err)
		}
		return payload.Count
	}
	if got := count(userA.AccessToken); got != 3 {
		t.Fatalf("user A unread count = %d, want 3", got)
	}
	if got := count(userB.AccessToken); got != 2 {
		t.Fatalf("user B unread count = %d, want 2", got)
	}

	readReq := httptest.NewRequest(http.MethodPatch, "/api/v1/notifications/"+notificationIDs[0]+"/read", nil)
	readReq.Header.Set("Authorization", "Bearer "+userA.AccessToken)
	readRes := httptest.NewRecorder()
	s.ServeHTTP(readRes, readReq)
	if readRes.Code != http.StatusOK {
		t.Fatalf("single read status=%d body=%s", readRes.Code, readRes.Body.String())
	}
	if got := count(userA.AccessToken); got != 2 {
		t.Fatalf("user A after single read = %d, want 2", got)
	}

	wrongUserReq := httptest.NewRequest(http.MethodPatch, "/api/v1/notifications/"+notificationIDs[0]+"/read", nil)
	wrongUserReq.Header.Set("Authorization", "Bearer "+userB.AccessToken)
	wrongUserRes := httptest.NewRecorder()
	s.ServeHTTP(wrongUserRes, wrongUserReq)
	if wrongUserRes.Code != http.StatusNotFound || !strings.Contains(wrongUserRes.Body.String(), `"code":"NOTIFICATION_NOT_FOUND"`) {
		t.Fatalf("cross-user read status=%d body=%s", wrongUserRes.Code, wrongUserRes.Body.String())
	}
	if got := count(userB.AccessToken); got != 2 {
		t.Fatalf("user B after cross-user read = %d, want 2", got)
	}

	allReq := httptest.NewRequest(http.MethodPost, "/api/v1/notifications/read-all", nil)
	allReq.Header.Set("Authorization", "Bearer "+userA.AccessToken)
	allRes := httptest.NewRecorder()
	s.ServeHTTP(allRes, allReq)
	if allRes.Code != http.StatusOK {
		t.Fatalf("read all status=%d body=%s", allRes.Code, allRes.Body.String())
	}
	if got := count(userA.AccessToken); got != 0 {
		t.Fatalf("user A after read all = %d, want 0", got)
	}
}
