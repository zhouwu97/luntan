package api

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

// TestLikePointsConcurrency 验证点赞并发时不会超发
// 场景：已有 4 次点赞积分，两个并发点赞同时到达
// 预期：只有一个能获得第 5 次积分，最终只有 5 条点赞积分流水
func TestLikePointsConcurrency(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())

	// 创建点赞用户
	likerSession, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "liker_concurrent_" + suffix,
		Password: "安全密码12345",
		Nickname: "并发点赞",
	}, auth.SessionMetadata{UserAgent: "like-concurrent-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	// 创建帖子作者
	authorSession, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "author_" + suffix,
		Password: "安全密码12345",
		Nickname: "作者",
	}, auth.SessionMetadata{UserAgent: "like-concurrent-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	// 给作者管理员权限
	if _, err := s.db.Exec(`
		INSERT INTO user_roles (id, user_id, role_id)
		SELECT $1, $2, id FROM roles WHERE name = 'super_admin' LIMIT 1
		ON CONFLICT DO NOTHING`, "lptc-role-"+suffix, authorSession.User.ID); err != nil {
		t.Fatal(err)
	}

	// 创建社区和 6 个帖子
	categoryID := "lptc-cat-" + suffix
	communityID := "lptc-com-" + suffix
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, 'lptc', $2)`, categoryID, "lptc-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, 'lptc', 'active')`, communityID, categoryID, "lptc-"+suffix); err != nil {
		t.Fatal(err)
	}

	postIDs := make([]string, 6)
	for i := 0; i < 6; i++ {
		postID := fmt.Sprintf("lptc-post-%d-%s", i, suffix)
		postIDs[i] = postID
		if _, err := s.db.Exec(`
			INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at)
			VALUES ($1, $2, $3, 'normal', 'published', 'normal', $4, 'content', now())`,
			postID, authorSession.User.ID, communityID, fmt.Sprintf("帖子%d", i)); err != nil {
			t.Fatal(err)
		}
	}

	// 点赞函数
	likePost := func(postID string) int {
		req := httptest.NewRequest(http.MethodPut, "/api/v1/posts/"+postID+"/like", nil)
		req.Header.Set("Authorization", "Bearer "+likerSession.AccessToken)
		res := httptest.NewRecorder()
		NewHandler(s.db).ServeHTTP(res, req)
		return res.Code
	}

	// 先点赞前 4 个帖子
	for i := 0; i < 4; i++ {
		if code := likePost(postIDs[i]); code != http.StatusOK {
			t.Fatalf("点赞帖子 %d 失败: status=%d", i, code)
		}
	}

	// 验证已有 4 条点赞积分流水
	var likeCount int
	if err := s.db.QueryRow(`
		SELECT COUNT(*) FROM point_transactions
		WHERE user_id = $1 AND source = 'like' AND delta > 0
	`, likerSession.User.ID).Scan(&likeCount); err != nil {
		t.Fatal(err)
	}
	if likeCount != 4 {
		t.Fatalf("前 4 次点赞后积分流水 = %d, want 4", likeCount)
	}

	// 并发点赞第 5 和第 6 个帖子
	var wg sync.WaitGroup
	results := make([]int, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			results[idx] = likePost(postIDs[4+idx])
		}(i)
	}
	wg.Wait()

	// 两个请求都应该成功创建点赞记录
	for i, code := range results {
		if code != http.StatusOK {
			t.Fatalf("并发点赞 %d 失败: status=%d", i, code)
		}
	}

	// 验证只有 5 条点赞积分流水（第 6 个点赞不应获得积分）
	if err := s.db.QueryRow(`
		SELECT COUNT(*) FROM point_transactions
		WHERE user_id = $1 AND source = 'like' AND delta > 0
	`, likerSession.User.ID).Scan(&likeCount); err != nil {
		t.Fatal(err)
	}
	if likeCount != 5 {
		t.Fatalf("并发点赞后积分流水 = %d, want 5 (第6次不获得积分)", likeCount)
	}

	// 验证用户最终积分为 5
	var finalBalance int64
	if err := s.db.QueryRow(`SELECT points_balance FROM users WHERE id = $1`, likerSession.User.ID).Scan(&finalBalance); err != nil {
		t.Fatal(err)
	}
	if finalBalance != 5 {
		t.Fatalf("并发点赞后积分 = %d, want 5", finalBalance)
	}
}

// TestLikePointsDailyLimit 验证点赞每天只有前 5 次获得积分
func TestLikePointsDailyLimit(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())

	likerSession, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "liker_limit_" + suffix,
		Password: "安全密码12345",
		Nickname: "限额点赞",
	}, auth.SessionMetadata{UserAgent: "like-limit-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	authorSession, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "author_limit_" + suffix,
		Password: "安全密码12345",
		Nickname: "作者",
	}, auth.SessionMetadata{UserAgent: "like-limit-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := s.db.Exec(`
		INSERT INTO user_roles (id, user_id, role_id)
		SELECT $1, $2, id FROM roles WHERE name = 'super_admin' LIMIT 1
		ON CONFLICT DO NOTHING`, "lptl-role-"+suffix, authorSession.User.ID); err != nil {
		t.Fatal(err)
	}

	categoryID := "lptl-cat-" + suffix
	communityID := "lptl-com-" + suffix
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, 'lptl', $2)`, categoryID, "lptl-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, 'lptl', 'active')`, communityID, categoryID, "lptl-"+suffix); err != nil {
		t.Fatal(err)
	}

	// 创建 7 个帖子
	postIDs := make([]string, 7)
	for i := 0; i < 7; i++ {
		postID := fmt.Sprintf("lptl-post-%d-%s", i, suffix)
		postIDs[i] = postID
		if _, err := s.db.Exec(`
			INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at)
			VALUES ($1, $2, $3, 'normal', 'published', 'normal', $4, 'content', now())`,
			postID, authorSession.User.ID, communityID, fmt.Sprintf("帖子%d", i)); err != nil {
			t.Fatal(err)
		}
	}

	// 点赞函数
	likePost := func(postID string) {
		req := httptest.NewRequest(http.MethodPut, "/api/v1/posts/"+postID+"/like", nil)
		req.Header.Set("Authorization", "Bearer "+likerSession.AccessToken)
		res := httptest.NewRecorder()
		NewHandler(s.db).ServeHTTP(res, req)
		if res.Code != http.StatusOK {
			t.Fatalf("点赞失败: status=%d body=%s", res.Code, res.Body.String())
		}
	}

	// 点赞 7 个帖子
	for i := 0; i < 7; i++ {
		likePost(postIDs[i])
	}

	// 验证只有 5 条点赞积分流水
	var likeCount int
	if err := s.db.QueryRow(`
		SELECT COUNT(*) FROM point_transactions
		WHERE user_id = $1 AND source = 'like' AND delta > 0
	`, likerSession.User.ID).Scan(&likeCount); err != nil {
		t.Fatal(err)
	}
	if likeCount != 5 {
		t.Fatalf("点赞 7 次后积分流水 = %d, want 5", likeCount)
	}

	// 验证用户最终积分为 5
	var finalBalance int64
	if err := s.db.QueryRow(`SELECT points_balance FROM users WHERE id = $1`, likerSession.User.ID).Scan(&finalBalance); err != nil {
		t.Fatal(err)
	}
	if finalBalance != 5 {
		t.Fatalf("点赞 7 次后积分 = %d, want 5", finalBalance)
	}
}
