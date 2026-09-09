package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestRecordPostShareKeepsBaselineAndDeduplicates(t *testing.T) {
	s := feedIntegrationServer(t)
	communityID, _ := insertFeedFixtures(t, s)
	handler := NewHandler(s.db)
	suffix := time.Now().UnixNano()

	authorEmail := fmt.Sprintf("itest-share-author-%d@example.com", suffix)
	authorToken := registerAndLogin(t, handler, authorEmail, fmt.Sprintf("share_author_%d", suffix%100000000), "password123")
	sharerToken := registerAndLogin(t, handler, fmt.Sprintf("itest-share-user-%d@example.com", suffix), fmt.Sprintf("share_user_%d", suffix%100000000), "password123")
	concurrentToken := registerAndLogin(t, handler, fmt.Sprintf("itest-share-concurrent-%d@example.com", suffix), fmt.Sprintf("share_concurrent_%d", suffix%100000000), "password123")

	var authorID string
	if err := s.db.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, authorEmail).Scan(&authorID); err != nil {
		t.Fatal(err)
	}
	postID := fmt.Sprintf("itest-share-post-%d", suffix)
	if _, err := s.db.Exec(`
		INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status,
			title, content, share_count, created_at, updated_at, published_at)
		VALUES ($1, $2, $3, 'normal', 'published', 'normal', '分享计数测试', '正文', 7, now(), now(), now())`,
		postID, authorID, communityID); err != nil {
		t.Fatal(err)
	}

	record := func(token string) (int, map[string]any) {
		code, body := callBusinessAPI(handler, http.MethodPost, "/api/v1/posts/"+postID+"/share", token, nil, nil)
		var payload map[string]any
		_ = json.Unmarshal(body, &payload)
		return code, payload
	}

	if code, payload := record(""); code != http.StatusUnauthorized {
		t.Fatalf("未登录分享计数 status=%d payload=%v", code, payload)
	}
	guest, err := auth.NewService(s.db).CreateGuest(context.Background(), auth.SessionMetadata{UserAgent: "share-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	if code, payload := record(guest.AccessToken); code != http.StatusForbidden {
		t.Fatalf("游客分享计数 status=%d payload=%v", code, payload)
	}
	if code, payload := record(authorToken); code != http.StatusOK || payload["recorded"] != false || payload["share_count"] != float64(7) {
		t.Fatalf("作者分享不应计数 status=%d payload=%v", code, payload)
	}
	if code, payload := record(sharerToken); code != http.StatusOK || payload["recorded"] != true || payload["share_count"] != float64(8) {
		t.Fatalf("首次分享应保留基线并增加 1 status=%d payload=%v", code, payload)
	}
	if code, payload := record(sharerToken); code != http.StatusOK || payload["recorded"] != false || payload["share_count"] != float64(8) {
		t.Fatalf("重复分享应幂等 status=%d payload=%v", code, payload)
	}

	var recorded int32
	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			code, payload := record(concurrentToken)
			if code == http.StatusOK && payload["recorded"] == true {
				atomic.AddInt32(&recorded, 1)
			}
		}()
	}
	wg.Wait()
	if recorded != 1 {
		t.Fatalf("并发重复分享 recorded=%d, want 1", recorded)
	}

	var shareCount, eventCount int
	if err := s.db.QueryRow(`SELECT share_count FROM posts WHERE id = $1`, postID).Scan(&shareCount); err != nil {
		t.Fatal(err)
	}
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM post_share_events WHERE post_id = $1`, postID).Scan(&eventCount); err != nil {
		t.Fatal(err)
	}
	if shareCount != 9 || eventCount != 2 {
		t.Fatalf("最终分享聚合错误 share_count=%d events=%d", shareCount, eventCount)
	}

	if _, err := s.db.Exec(`UPDATE communities SET status = 'inactive' WHERE id = $1`, communityID); err != nil {
		t.Fatal(err)
	}
	if code, payload := record(sharerToken); code != http.StatusNotFound {
		t.Fatalf("停用社区中的帖子不可分享计数 status=%d payload=%v", code, payload)
	}
	if _, err := s.db.Exec(`UPDATE communities SET status = 'active', deleted_at = now() WHERE id = $1`, communityID); err != nil {
		t.Fatal(err)
	}
	if code, payload := record(sharerToken); code != http.StatusNotFound {
		t.Fatalf("已删除社区中的帖子不可分享计数 status=%d payload=%v", code, payload)
	}
}
