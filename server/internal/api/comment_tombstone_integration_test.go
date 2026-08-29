package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

// 根评论删除后楼中楼不应孤儿化：有可见回复的已删根评论以墓碑占位返回，
// 回复线程仍可进入，帖子计数只扣根评论本身；无回复的根评论删除后消失。
func TestDeleteRootCommentKeepsTombstoneAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "tombstone_author_" + suffix,
		Password: "安全密码12345",
		Nickname: "墓碑测试",
	}, auth.SessionMetadata{UserAgent: "comment-integration-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	categoryID := "tombstone-cat-" + suffix
	communityID := "tombstone-community-" + suffix
	postID := "tombstone-post-" + suffix
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, 'tombstone', $2)`, categoryID, "tombstone-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, 'tombstone', 'active')`, communityID, categoryID, "tombstone-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at) VALUES ($1, $2, $3, 'normal', 'published', 'normal', 'tombstone', 'tombstone', now())`, postID, session.User.ID, communityID); err != nil {
		t.Fatal(err)
	}

	now := time.Now().UTC()
	rootWithReplies := "tombstone-root-a-" + suffix
	insertComment := func(id, rootID, parentID, content string, createdAt time.Time) {
		t.Helper()
		if _, err := s.db.Exec(`
			INSERT INTO comments (id, post_id, author_id, root_id, parent_id, content,
				publication_status, moderation_status, created_at, updated_at, published_at)
			VALUES ($1, $2, $3, $4, NULLIF($5, ''), $6, 'published', 'normal', $7, $7, $7)`,
			id, postID, session.User.ID, rootID, parentID, content, createdAt); err != nil {
			t.Fatal(err)
		}
	}
	insertComment(rootWithReplies, rootWithReplies, "", "被删楼层", now)
	for i, content := range []string{"回复一", "回复二"} {
		insertComment(fmt.Sprintf("tombstone-reply-%d-%s", i, suffix), rootWithReplies, rootWithReplies, content, now.Add(time.Duration(i)*time.Minute))
	}
	rootWithoutReplies := "tombstone-root-b-" + suffix
	insertComment(rootWithoutReplies, rootWithoutReplies, "", "无回复楼层", now.Add(2*time.Minute))

	deleteComment := func(commentID string) int {
		req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/"+commentID, nil)
		req.Header.Set("Authorization", "Bearer "+session.AccessToken)
		res := httptest.NewRecorder()
		NewHandler(s.db).ServeHTTP(res, req)
		return res.Code
	}
	if code := deleteComment(rootWithReplies); code != http.StatusNoContent {
		t.Fatalf("delete root with replies: status=%d", code)
	}
	if code := deleteComment(rootWithoutReplies); code != http.StatusNoContent {
		t.Fatalf("delete childless root: status=%d", code)
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/v1/posts/"+postID+"/comments", nil)
	listRes := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(listRes, listReq)
	if listRes.Code != http.StatusOK {
		t.Fatalf("list comments: status=%d body=%s", listRes.Code, listRes.Body.String())
	}
	var payload struct {
		Items []struct {
			ID          string `json:"id"`
			Content     string `json:"content"`
			Publication string `json:"publication_status"`
			ReplyCount  int64  `json:"reply_count"`
		} `json:"items"`
	}
	if err := json.Unmarshal(listRes.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Items) != 1 || payload.Items[0].ID != rootWithReplies {
		t.Fatalf("floors = %+v, want only tombstone %s", payload.Items, rootWithReplies)
	}
	tombstone := payload.Items[0]
	if tombstone.Publication != "deleted" || tombstone.Content != "" {
		t.Fatalf("tombstone must hide original content: %+v", tombstone)
	}
	if tombstone.ReplyCount != 2 {
		t.Fatalf("tombstone reply_count = %d, want 2", tombstone.ReplyCount)
	}

	repliesReq := httptest.NewRequest(http.MethodGet, "/api/v1/comments/"+rootWithReplies+"/replies", nil)
	repliesRes := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(repliesRes, repliesReq)
	if repliesRes.Code != http.StatusOK {
		t.Fatalf("replies of tombstone root: status=%d body=%s", repliesRes.Code, repliesRes.Body.String())
	}
	var replies struct {
		Items []struct {
			ID string `json:"id"`
		} `json:"items"`
	}
	if err := json.Unmarshal(repliesRes.Body.Bytes(), &replies); err != nil {
		t.Fatal(err)
	}
	if len(replies.Items) != 2 {
		t.Fatalf("tombstone replies = %d, want 2: %s", len(replies.Items), repliesRes.Body.String())
	}

	var commentCount int64
	if err := s.db.QueryRow(`SELECT comment_count FROM posts WHERE id = $1`, postID).Scan(&commentCount); err != nil {
		t.Fatal(err)
	}
	if commentCount != 2 {
		t.Fatalf("post comment_count = %d, want 2 (visible replies only)", commentCount)
	}
}
