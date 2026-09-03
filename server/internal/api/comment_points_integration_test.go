package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

// TestCommentCreationAwardsPoints 验证评论创建接口真正调用积分发放
func TestCommentCreationAwardsPoints(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())

	// 创建用户
	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "comment_points_" + suffix,
		Password: "安全密码12345",
		Nickname: "积分测试",
	}, auth.SessionMetadata{UserAgent: "comment-points-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	// 给用户管理员权限以便创建帖子
	if _, err := s.db.Exec(`
		INSERT INTO user_roles (id, user_id, role_id)
		SELECT $1, $2, id FROM roles WHERE name = 'super_admin' LIMIT 1
		ON CONFLICT DO NOTHING`, "cpts-role-"+suffix, session.User.ID); err != nil {
		t.Fatal(err)
	}

	// 创建社区和帖子
	categoryID := "cpts-cat-" + suffix
	communityID := "cpts-com-" + suffix
	postID := "cpts-post-" + suffix
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, 'cpts', $2)`, categoryID, "cpts-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, 'cpts', 'active')`, communityID, categoryID, "cpts-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at) VALUES ($1, $2, $3, 'normal', 'published', 'normal', 'cpts', 'cpts', now())`, postID, session.User.ID, communityID); err != nil {
		t.Fatal(err)
	}

	// 获取初始积分
	var initialBalance int64
	if err := s.db.QueryRow(`SELECT points_balance FROM users WHERE id = $1`, session.User.ID).Scan(&initialBalance); err != nil {
		t.Fatal(err)
	}

	// 创建根评论
	createComment := func(content string) string {
		body, _ := json.Marshal(map[string]interface{}{
			"post_id": postID,
			"content": content,
		})
		req := httptest.NewRequest(http.MethodPost, "/api/v1/comments", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+session.AccessToken)
		req.Header.Set("Content-Type", "application/json")
		res := httptest.NewRecorder()
		NewHandler(s.db).ServeHTTP(res, req)
		if res.Code != http.StatusCreated {
			t.Fatalf("create comment failed: status=%d body=%s", res.Code, res.Body.String())
		}
		var resp struct {
			ID string `json:"id"`
		}
		json.Unmarshal(res.Body.Bytes(), &resp)
		return resp.ID
	}

	// 第一条评论: +2 积分
	createComment("第一条评论")
	var balance1 int64
	if err := s.db.QueryRow(`SELECT points_balance FROM users WHERE id = $1`, session.User.ID).Scan(&balance1); err != nil {
		t.Fatal(err)
	}
	if balance1 != initialBalance+2 {
		t.Fatalf("第一条评论后积分 = %d, want %d", balance1, initialBalance+2)
	}

	// 第二条评论: 再 +2 积分
	createComment("第二条评论")
	var balance2 int64
	if err := s.db.QueryRow(`SELECT points_balance FROM users WHERE id = $1`, session.User.ID).Scan(&balance2); err != nil {
		t.Fatal(err)
	}
	if balance2 != initialBalance+4 {
		t.Fatalf("第二条评论后积分 = %d, want %d", balance2, initialBalance+4)
	}

	// 验证积分流水
	var txCount int
	if err := s.db.QueryRow(`
		SELECT COUNT(*) FROM point_transactions
		WHERE user_id = $1 AND source = 'comment' AND delta = 2
	`, session.User.ID).Scan(&txCount); err != nil {
		t.Fatal(err)
	}
	if txCount != 2 {
		t.Fatalf("评论积分流水数 = %d, want 2", txCount)
	}
}

// TestCommentPointsRespectsDailyLimit 验证评论积分受每日总上限约束
func TestCommentPointsRespectsDailyLimit(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())

	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "comment_limit_" + suffix,
		Password: "安全密码12345",
		Nickname: "限额测试",
	}, auth.SessionMetadata{UserAgent: "comment-limit-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := s.db.Exec(`
		INSERT INTO user_roles (id, user_id, role_id)
		SELECT $1, $2, id FROM roles WHERE name = 'super_admin' LIMIT 1
		ON CONFLICT DO NOTHING`, "cptl-role-"+suffix, session.User.ID); err != nil {
		t.Fatal(err)
	}

	categoryID := "cptl-cat-" + suffix
	communityID := "cptl-com-" + suffix
	postID := "cptl-post-" + suffix
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, 'cptl', $2)`, categoryID, "cptl-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, 'cptl', 'active')`, communityID, categoryID, "cptl-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at) VALUES ($1, $2, $3, 'normal', 'published', 'normal', 'cptl', 'cptl', now())`, postID, session.User.ID, communityID); err != nil {
		t.Fatal(err)
	}

	// 模拟用户当天已获得 19 积分
	if _, err := s.db.Exec(`
		INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key, created_at)
		VALUES ($1, $2, 'post', 19, 19, '模拟已获得积分', 'sim-19-'+$3,
			date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai')
	`, "sim-tx-"+suffix, session.User.ID, suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`UPDATE users SET points_balance = 19 WHERE id = $1`, session.User.ID); err != nil {
		t.Fatal(err)
	}

	// 创建评论：应该只获得 +1（因为 19+2 超过 20 上限）
	body, _ := json.Marshal(map[string]interface{}{
		"post_id": postID,
		"content": "接近上限的评论",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/comments", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	res := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(res, req)
	if res.Code != http.StatusCreated {
		t.Fatalf("create comment failed: status=%d body=%s", res.Code, res.Body.String())
	}

	var finalBalance int64
	if err := s.db.QueryRow(`SELECT points_balance FROM users WHERE id = $1`, session.User.ID).Scan(&finalBalance); err != nil {
		t.Fatal(err)
	}
	if finalBalance != 20 {
		t.Fatalf("达到上限后积分 = %d, want 20", finalBalance)
	}

	// 验证评论积分流水：delta 应该是 1 而不是 2
	var commentDelta int64
	if err := s.db.QueryRow(`
		SELECT delta FROM point_transactions
		WHERE user_id = $1 AND source = 'comment' AND idempotency_key LIKE 'comment:create:%'
	`, session.User.ID).Scan(&commentDelta); err != nil {
		t.Fatal(err)
	}
	if commentDelta != 1 {
		t.Fatalf("评论积分 delta = %d, want 1 (被上限截断)", commentDelta)
	}
}

// TestCommentPointsBlockedAtDailyLimit 验证达到上限后评论不再获得积分
func TestCommentPointsBlockedAtDailyLimit(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())

	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "comment_blocked_" + suffix,
		Password: "安全密码12345",
		Nickname: "封顶测试",
	}, auth.SessionMetadata{UserAgent: "comment-blocked-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := s.db.Exec(`
		INSERT INTO user_roles (id, user_id, role_id)
		SELECT $1, $2, id FROM roles WHERE name = 'super_admin' LIMIT 1
		ON CONFLICT DO NOTHING`, "cptb-role-"+suffix, session.User.ID); err != nil {
		t.Fatal(err)
	}

	categoryID := "cptb-cat-" + suffix
	communityID := "cptb-com-" + suffix
	postID := "cptb-post-" + suffix
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, 'cptb', $2)`, categoryID, "cptb-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, 'cptb', 'active')`, communityID, categoryID, "cptb-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at) VALUES ($1, $2, $3, 'normal', 'published', 'normal', 'cptb', 'cptb', now())`, postID, session.User.ID, communityID); err != nil {
		t.Fatal(err)
	}

	// 模拟用户当天已获得 20 积分（达到上限）
	if _, err := s.db.Exec(`
		INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key, created_at)
		VALUES ($1, $2, 'post', 20, 20, '模拟已达上限', 'sim-20-'+$3,
			date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai')
	`, "sim-tx-"+suffix, session.User.ID, suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`UPDATE users SET points_balance = 20 WHERE id = $1`, session.User.ID); err != nil {
		t.Fatal(err)
	}

	// 创建评论：应该不再获得积分
	body, _ := json.Marshal(map[string]interface{}{
		"post_id": postID,
		"content": "达到上限后的评论",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/comments", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	res := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(res, req)
	if res.Code != http.StatusCreated {
		t.Fatalf("create comment failed: status=%d body=%s", res.Code, res.Body.String())
	}

	var finalBalance int64
	if err := s.db.QueryRow(`SELECT points_balance FROM users WHERE id = $1`, session.User.ID).Scan(&finalBalance); err != nil {
		t.Fatal(err)
	}
	if finalBalance != 20 {
		t.Fatalf("达到上限后评论，积分 = %d, want 20 (不变)", finalBalance)
	}

	// 验证没有新的评论积分流水
	var commentTxCount int
	if err := s.db.QueryRow(`
		SELECT COUNT(*) FROM point_transactions
		WHERE user_id = $1 AND source = 'comment'
	`, session.User.ID).Scan(&commentTxCount); err != nil {
		t.Fatal(err)
	}
	if commentTxCount != 0 {
		t.Fatalf("达到上限后不应产生评论积分流水，实际 = %d", commentTxCount)
	}
}
