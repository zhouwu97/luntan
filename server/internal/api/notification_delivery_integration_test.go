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

func TestInteractionNotificationJourneyAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	s.authService = auth.NewService(s.db)
	_, posts := insertFeedFixtures(t, s)
	suffix := fmt.Sprint(time.Now().UnixNano())
	register := func(name string) auth.AuthResponse {
		t.Helper()
		session, err := s.authService.Register(context.Background(), auth.RegisterInput{
			Username: "notice_" + name + suffix, Password: "TestPassword123!", Nickname: name,
		}, auth.SessionMetadata{})
		if err != nil {
			t.Fatal(err)
		}
		return session
	}
	a, b := register("a"), register("b")
	post := posts["p1"]
	if _, err := s.db.Exec(`UPDATE posts SET author_id = $1 WHERE id = $2`, a.User.ID, post); err != nil {
		t.Fatal(err)
	}
	comment := "notice-comment-" + suffix
	if _, err := s.db.Exec(`INSERT INTO comments (id, post_id, author_id, content, publication_status, moderation_status)
        VALUES ($1, $2, $3, '测试评论', 'published', 'normal')`, comment, post, a.User.ID); err != nil {
		t.Fatal(err)
	}
	request := func(method, path, token, body string) {
		t.Helper()
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+token)
		rec := httptest.NewRecorder()
		s.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s %s: %d %s", method, path, rec.Code, rec.Body.String())
		}
	}
	for _, action := range []struct{ path, kind, target string }{
		{"/api/v1/posts/" + post + "/bookmark", "bookmark", post},
		{"/api/v1/comments/" + comment + "/like", "like", comment},
		{"/api/v1/users/" + a.User.ID + "/follow", "follow", b.User.ID},
	} {
		// 重复 PUT 只能产生一次通知；取消操作也不能新增通知。
		request("PUT", action.path, b.AccessToken, "")
		request("PUT", action.path, b.AccessToken, "")
		request("DELETE", action.path, b.AccessToken, "")
		var count int
		if err := s.db.QueryRow(`SELECT count(*) FROM notifications n JOIN outbox_events o ON o.aggregate_id = n.id
            WHERE n.user_id = $1 AND n.actor_id = $2 AND n.type = $3 AND n.target_id = $4
              AND o.event_type = 'notification.created'`, a.User.ID, b.User.ID, action.kind, action.target).Scan(&count); err != nil {
			t.Fatal(err)
		}
		if count != 1 {
			t.Fatalf("%s 通知及 outbox 数量 = %d", action.kind, count)
		}
	}
	var folderID string
	if err := s.db.QueryRow(`SELECT id FROM bookmark_folders WHERE user_id = $1 AND is_default`, b.User.ID).Scan(&folderID); err != nil {
		t.Fatal(err)
	}
	folderBody := `{"folder_ids":["` + folderID + `"]}`
	request("PUT", "/api/v1/posts/"+posts["p2"]+"/bookmark-folders", b.AccessToken, folderBody)
	request("PUT", "/api/v1/posts/"+posts["p2"]+"/bookmark-folders", b.AccessToken, folderBody)
	var folderNotices int
	if err := s.db.QueryRow(`SELECT count(*) FROM notifications WHERE actor_id=$1 AND target_id=$2 AND type='bookmark'`, b.User.ID, posts["p2"]).Scan(&folderNotices); err != nil || folderNotices != 1 {
		t.Fatalf("收藏夹通知=%d err=%v", folderNotices, err)
	}

	var postID string
	if err := s.db.QueryRow(`SELECT target_data->>'post_id' FROM notifications WHERE user_id = $1 AND target_id = $2`, a.User.ID, comment).Scan(&postID); err != nil || postID != post {
		t.Fatalf("评论跳转 post_id=%q err=%v", postID, err)
	}
	request("PUT", "/api/v1/posts/"+post+"/bookmark", a.AccessToken, "")
	request("PUT", "/api/v1/comments/"+comment+"/like", a.AccessToken, "")
	var selfCount int
	if err := s.db.QueryRow(`SELECT count(*) FROM notifications WHERE user_id = $1 AND actor_id = $1`, a.User.ID).Scan(&selfCount); err != nil || selfCount != 0 {
		t.Fatalf("自通知=%d err=%v", selfCount, err)
	}
}

func TestActivityNotificationIsTransactionalAndOnceAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	s.authService = auth.NewService(s.db)
	suffix := fmt.Sprint(time.Now().UnixNano())
	admin, err := s.authService.Register(context.Background(), auth.RegisterInput{Username: "activity_notice_" + suffix, Password: "TestPassword123!"}, auth.SessionMetadata{})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO user_roles (id, user_id, role_id) VALUES ($1, $2, 'role-super-admin')`, newPostID(), admin.User.ID); err != nil {
		t.Fatal(err)
	}
	// 保证空数据库也至少有一个广播接收者。
	recipient, err := s.authService.Register(context.Background(), auth.RegisterInput{Username: "activity_recipient_" + suffix, Password: "TestPassword123!"}, auth.SessionMetadata{})
	if err != nil {
		t.Fatal(err)
	}
	call := func(path, body string, create bool) string {
		t.Helper()
		method := "POST"
		if strings.Contains(path, "/admin/activities/") && !strings.HasSuffix(path, "/publish") {
			method = "PUT"
		}
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+admin.AccessToken)
		rec := httptest.NewRecorder()
		s.ServeHTTP(rec, req)
		expected := 200
		if create {
			expected = 201
		}
		if rec.Code != expected {
			t.Fatalf("%s %s: %d %s", method, path, rec.Code, rec.Body.String())
		}
		var result struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		return result.ID
	}
	count := func(id string) int {
		var value int
		if err := s.db.QueryRow(`SELECT count(*) FROM notifications n JOIN outbox_events o ON o.aggregate_id = n.id
          WHERE n.target_type = 'activity' AND n.target_id = $1 AND o.event_type = 'notification.created'`, id).Scan(&value); err != nil {
			t.Fatal(err)
		}
		return value
	}
	for _, mode := range []string{"direct", "publish", "edit"} {
		status := "draft"
		if mode == "direct" {
			status = "active"
		}
		id := call("/api/v1/admin/activities", `{"title":"通知测试","status":"`+status+`"}`, true)
		if mode != "direct" && count(id) != 0 {
			t.Fatal("草稿不能发通知")
		}
		if mode == "publish" {
			call("/api/v1/admin/activities/"+id+"/publish", "", false)
		}
		if mode == "edit" {
			call("/api/v1/admin/activities/"+id, `{"title":"编辑发布","status":"active"}`, false)
		}
		original := count(id)
		if original == 0 {
			t.Fatalf("%s 没有广播", mode)
		}
		call("/api/v1/admin/activities/"+id+"/publish", "", false)
		if count(id) != original {
			t.Fatal("重复发布产生重复通知")
		}
	}
	// 发布事务回滚时，广播资格、通知和 outbox 必须一起撤销。
	rollbackID := call("/api/v1/admin/activities", `{"title":"回滚测试","status":"draft"}`, true)
	tx, err := s.db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`UPDATE activities SET publication_status='published' WHERE id=$1`, rollbackID); err != nil {
		t.Fatal(err)
	}
	if err := enqueueActivityNotificationTx(context.Background(), tx, rollbackID, admin.User.ID, time.Now().UTC()); err != nil {
		t.Fatal(err)
	}
	if err := tx.Rollback(); err != nil {
		t.Fatal(err)
	}
	if count(rollbackID) != 0 {
		t.Fatal("回滚事务泄漏通知")
	}

	announcementID := "announcement-" + suffix
	body := `{"id":"` + announcementID + `","title":"社区公告","content":"公告正文"}`
	call("/api/v1/admin/announcements", body, false)
	call("/api/v1/admin/announcements", body, false)
	var announcementCount int
	if err := s.db.QueryRow(`SELECT count(*) FROM notifications n JOIN outbox_events o ON o.aggregate_id=n.id WHERE n.target_id=$1 AND n.user_id=$2 AND n.type='community.announcement'`, announcementID, recipient.User.ID).Scan(&announcementCount); err != nil || announcementCount != 1 {
		t.Fatalf("公告重试通知=%d err=%v", announcementCount, err)
	}
	unauthorized := httptest.NewRequest("POST", "/api/v1/admin/announcements", strings.NewReader(body))
	unauthorized.Header.Set("Authorization", "Bearer "+recipient.AccessToken)
	response := httptest.NewRecorder()
	s.ServeHTTP(response, unauthorized)
	if response.Code != http.StatusForbidden {
		t.Fatalf("普通用户发布公告状态=%d", response.Code)
	}

}
