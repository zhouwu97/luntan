package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// 回归：全新库执行完 migration 后必须自带官方社区，否则任何发帖都会被
// COMMUNITY_NOT_FOUND 拒绝（社区此前只存在于禁止生产执行的 dev seed）。
func TestMigrationsSeedOfficialCommunities(t *testing.T) {
	s := feedIntegrationServer(t)

	var count int
	if err := s.db.QueryRow(`SELECT count(*) FROM communities WHERE status = 'active' AND deleted_at IS NULL`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count == 0 {
		t.Fatal("全新库迁移完成后没有任何 active 社区，用户将无法发帖")
	}
	for _, id := range []string{"community-unboxing", "community-campus", "community-daily"} {
		var exists bool
		if err := s.db.QueryRow(`SELECT EXISTS (SELECT 1 FROM communities WHERE id = $1 AND status = 'active')`, id).Scan(&exists); err != nil {
			t.Fatal(err)
		}
		if !exists {
			t.Fatalf("官方社区 %s 缺失", id)
		}
	}
}

// 回归：/admin/recommendations 曾经用 hasPermission(..., caseID="", ...) 做鉴权，
// 空 caseID 查不到 moderation_cases 导致连超级管理员都被 403，首页推荐管理整体不可用。
func TestRecommendationsAccessibleToSuperAdmin(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)

	suffix := time.Now().UnixNano()
	email := fmt.Sprintf("itest-rec-%d@example.com", suffix)
	username := fmt.Sprintf("itest_rec_%d", suffix%100000000)

	token := registerAndLogin(t, handler, email, username, "password123")
	promoteSuperAdmin(t, s, email)
	token = loginUser(t, handler, email, "password123")

	code, body := callBusinessAPI(handler, http.MethodGet, "/api/v1/admin/recommendations", token, nil, nil)
	if code != http.StatusOK {
		t.Fatalf("超级管理员读取推荐列表应返回 200，实际 %d：%s", code, body)
	}
}

// registerAndLogin 走真实注册流程并登录，返回 access token。
func registerAndLogin(t *testing.T, handler http.Handler, email, username, password string) string {
	t.Helper()
	codeBody, _ := json.Marshal(map[string]string{"email": email, "purpose": "register"})
	codeReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/code/request", bytes.NewReader(codeBody))
	codeRec := httptest.NewRecorder()
	handler.ServeHTTP(codeRec, codeReq)
	var codeResp map[string]any
	_ = json.Unmarshal(codeRec.Body.Bytes(), &codeResp)
	devCode, _ := codeResp["dev_code"].(string)
	if devCode == "" {
		t.Fatalf("dev_code 缺失：%s", codeRec.Body.String())
	}
	regBody, _ := json.Marshal(map[string]string{
		"email": email, "code": devCode, "password": password, "username": username,
	})
	regReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(regBody))
	regRec := httptest.NewRecorder()
	handler.ServeHTTP(regRec, regReq)
	if regRec.Code != http.StatusCreated {
		t.Fatalf("注册失败：%d %s", regRec.Code, regRec.Body.String())
	}
	return loginUser(t, handler, email, password)
}

func loginUser(t *testing.T, handler http.Handler, email, password string) string {
	t.Helper()
	body, _ := json.Marshal(map[string]string{"email": email, "password": password})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("登录失败：%d %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	token, _ := resp["access_token"].(string)
	if token == "" {
		t.Fatalf("登录未返回 access_token：%s", rec.Body.String())
	}
	return token
}

// promoteSuperAdmin 直接授予 super_admin 角色，用于构造管理员场景。
func promoteSuperAdmin(t *testing.T, s *Server, email string) {
	t.Helper()
	var userID, roleID string
	if err := s.db.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, email).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := s.db.QueryRow(`SELECT id FROM roles WHERE name = 'super_admin'`).Scan(&roleID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO user_roles (id, user_id, role_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
		"ur-"+userID+"-"+roleID, userID, roleID); err != nil {
		t.Fatal(err)
	}
}

func TestRecommendationExpiryAndVisibilityValidation(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)

	suffix := time.Now().UnixNano()
	email := fmt.Sprintf("itest-rec-val-%d@example.com", suffix)
	username := fmt.Sprintf("itest_rec_val_%d", suffix%100000000)

	token := registerAndLogin(t, handler, email, username, "password123")
	promoteSuperAdmin(t, s, email)
	token = loginUser(t, handler, email, "password123")

	// 1. 创建普通帖子并发布
	var authorID string
	_ = s.db.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, email).Scan(&authorID)
	now := time.Now().UTC()
	postID := fmt.Sprintf("post-rec-val-%d", suffix%100000)
	_, err := s.db.Exec(`
		INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at, created_at, updated_at)
		VALUES ($1, $2, 'community-campus', 'normal', 'published', 'normal', '测试推荐标题', '测试正文', $3, $3, $3)`,
		postID, authorID, now,
	)
	if err != nil {
		t.Fatal(err)
	}

	// 2. 过期时间早于当前时间 -> 400 INVALID_RECOMMENDATION_EXPIRY
	pastTime := now.Add(-1 * time.Hour)
	pastPayload, _ := json.Marshal(map[string]any{"expires_at": pastTime})
	code, body := callBusinessAPI(handler, http.MethodPut, "/api/v1/admin/recommendations/"+postID, token, pastPayload, nil)
	if code != http.StatusBadRequest {
		t.Fatalf("过去时间 expires_at 应返回 400，实际 %d：%s", code, body)
	}

	// 3. 处于 hidden 审核状态的帖子 -> 400 POST_NOT_RECOMMENDABLE
	hiddenPostID := postID + "-hidden"
	_, err = s.db.Exec(`
		INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at, created_at, updated_at)
		VALUES ($1, $2, 'community-campus', 'normal', 'published', 'hidden', '隐藏帖子', '测试正文', $3, $3, $3)`,
		hiddenPostID, authorID, now,
	)
	if err != nil {
		t.Fatal(err)
	}
	code, body = callBusinessAPI(handler, http.MethodPut, "/api/v1/admin/recommendations/"+hiddenPostID, token, nil, nil)
	if code != http.StatusBadRequest {
		t.Fatalf("hidden 帖子加入推荐应返回 400，实际 %d：%s", code, body)
	}

	// 4. 正常合规帖子设置未来过期时间 -> 200
	futureTime := now.Add(24 * time.Hour)
	futurePayload, _ := json.Marshal(map[string]any{"expires_at": futureTime})
	code, body = callBusinessAPI(handler, http.MethodPut, "/api/v1/admin/recommendations/"+postID, token, futurePayload, nil)
	if code != http.StatusOK {
		t.Fatalf("正常推荐应返回 200，实际 %d：%s", code, body)
	}
}

func TestActivityAdminFiltersAndEndedPublishValidation(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)

	suffix := time.Now().UnixNano()
	email := fmt.Sprintf("itest-act-val-%d@example.com", suffix)
	username := fmt.Sprintf("itest_act_val_%d", suffix%100000000)

	token := registerAndLogin(t, handler, email, username, "password123")
	promoteSuperAdmin(t, s, email)
	token = loginUser(t, handler, email, "password123")

	var adminID string
	_ = s.db.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, email).Scan(&adminID)

	now := time.Now().UTC()

	// 写入接口收到旧客户端可能提交的 phase 值时，数据库只保存发布状态，
	// 读取接口再根据时间计算 phase，验证写入和读取不会互相矛盾。
	createCode, createBody := callBusinessAPI(handler, http.MethodPost, "/api/v1/admin/activities", token, map[string]any{
		"title":  "状态机写读一致性活动",
		"status": "ended",
	}, nil)
	if createCode != http.StatusCreated {
		t.Fatalf("创建活动应返回 201，实际 %d：%s", createCode, createBody)
	}
	var created struct {
		ID                string `json:"id"`
		Status            string `json:"status"`
		PublicationStatus string `json:"publication_status"`
		Phase             string `json:"phase"`
	}
	if err := json.Unmarshal(createBody, &created); err != nil {
		t.Fatal(err)
	}
	if created.ID == "" || created.Status != "active" || created.PublicationStatus != "published" || created.Phase != "active" {
		t.Fatalf("活动写入响应状态不一致：%s", createBody)
	}
	var storedStatus, storedPublicationStatus string
	if err := s.db.QueryRow(`SELECT status, publication_status FROM activities WHERE id = $1`, created.ID).Scan(&storedStatus, &storedPublicationStatus); err != nil {
		t.Fatal(err)
	}
	if storedStatus != "active" || storedPublicationStatus != "published" {
		t.Fatalf("活动数据库状态不一致：status=%q publication_status=%q", storedStatus, storedPublicationStatus)
	}

	// 1. 创建已结束活动草稿（end_at 在过去）
	endedActID := fmt.Sprintf("act-ended-%d", suffix%100000)
	pastStart := now.Add(-48 * time.Hour)
	pastEnd := now.Add(-24 * time.Hour)
	_, err := s.db.Exec(`
		INSERT INTO activities (id, title, description, start_at, end_at, status, created_by, created_at, updated_at)
		VALUES ($1, '已结束活动', '描述', $2, $3, 'draft', $4, $5, $5)`,
		endedActID, pastStart, pastEnd, adminID, now,
	)
	if err != nil {
		t.Fatal(err)
	}

	// 发布已结束活动应返回 409 ACTIVITY_ALREADY_ENDED
	code, body := callBusinessAPI(handler, http.MethodPost, "/api/v1/admin/activities/"+endedActID+"/publish", token, nil, nil)
	if code != http.StatusConflict {
		t.Fatalf("发布已结束活动应返回 409 Conflict，实际 %d：%s", code, body)
	}

	// 2. 创建一个进行中活动（start_at 在过去，end_at 在未来，status 存为 active）
	activeActID := fmt.Sprintf("act-active-%d", suffix%100000)
	futureEnd := now.Add(24 * time.Hour)
	_, err = s.db.Exec(`
		INSERT INTO activities (id, title, description, start_at, end_at, status, publication_status, created_by, published_at, created_at, updated_at)
		VALUES ($1, '进行中活动', '描述', $2, $3, 'active', 'published', $4, $5, $5, $5)`,
		activeActID, pastStart, futureEnd, adminID, now,
	)
	if err != nil {
		t.Fatal(err)
	}

	// 管理员按 status=active 筛选 -> 必须包含该活动
	code, body = callBusinessAPI(handler, http.MethodGet, "/api/v1/admin/activities?status=active", token, nil, nil)
	if code != http.StatusOK {
		t.Fatalf("筛选 active 活动应返回 200，实际 %d：%s", code, body)
	}
	var resp map[string]any
	_ = json.Unmarshal(body, &resp)
	items, _ := resp["items"].([]any)
	found := false
	for _, it := range items {
		if m, ok := it.(map[string]any); ok && m["id"] == activeActID {
			found = true
			if m["status"] != "active" || m["publication_status"] != "published" || m["phase"] != "active" {
				t.Fatalf("活动状态应派生为 active，实际 status=%v publication_status=%v phase=%v", m["status"], m["publication_status"], m["phase"])
			}
		}
	}
	if !found {
		t.Fatalf("status=upcoming 筛选列表中不应包含进行中活动 %s", activeActID)
	}
}

// 回归：帖子被管理员上首页推荐时，作者一次性获得 +20 积分（不受每日积分上限
// 约束）；取消推荐不扣分；取消后再推荐因幂等键按帖子维度，不会重复发放。
func TestRecommendationAwardsAuthorPointsOnce(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)

	suffix := time.Now().UnixNano()
	adminEmail := fmt.Sprintf("itest-rec-pts-admin-%d@example.com", suffix)
	authorEmail := fmt.Sprintf("itest-rec-pts-author-%d@example.com", suffix)

	adminToken := registerAndLogin(t, handler, adminEmail, fmt.Sprintf("itest_rec_pts_admin_%d", suffix%100000000), "password123")
	promoteSuperAdmin(t, s, adminEmail)
	adminToken = loginUser(t, handler, adminEmail, "password123")

	_ = registerAndLogin(t, handler, authorEmail, fmt.Sprintf("itest_rec_pts_author_%d", suffix%100000000), "password123")
	var authorID string
	if err := s.db.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, authorEmail).Scan(&authorID); err != nil {
		t.Fatal(err)
	}

	// 直接 SQL 插入已发布帖子，避免发帖积分干扰推荐积分断言。
	now := time.Now().UTC()
	postID := fmt.Sprintf("post-rec-pts-%d", suffix%100000)
	if _, err := s.db.Exec(`
		INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at, created_at, updated_at)
		VALUES ($1, $2, 'community-campus', 'normal', 'published', 'normal', '推荐积分测试帖', '测试正文', $3, $3, $3)`,
		postID, authorID, now,
	); err != nil {
		t.Fatal(err)
	}

	balanceOf := func() int64 {
		t.Helper()
		var balance int64
		if err := s.db.QueryRow(`SELECT points_balance FROM users WHERE id = $1`, authorID).Scan(&balance); err != nil {
			t.Fatal(err)
		}
		return balance
	}
	recommendTxCount := func() int {
		t.Helper()
		var count int
		if err := s.db.QueryRow(`SELECT COUNT(*) FROM point_transactions WHERE user_id = $1 AND source = 'recommend' AND idempotency_key = $2`, authorID, "post:recommend:"+postID).Scan(&count); err != nil {
			t.Fatal(err)
		}
		return count
	}

	initial := balanceOf()

	// 1. 上推荐 -> 作者 +20，产生一条推荐流水。
	code, body := callBusinessAPI(handler, http.MethodPut, "/api/v1/admin/recommendations/"+postID, adminToken, nil, nil)
	if code != http.StatusOK {
		t.Fatalf("上推荐应返回 200，实际 %d：%s", code, body)
	}
	if got := balanceOf(); got != initial+20 {
		t.Fatalf("上推荐后作者余额=%d, want %d", got, initial+20)
	}
	if got := recommendTxCount(); got != 1 {
		t.Fatalf("上推荐后推荐流水=%d, want 1", got)
	}

	// 2. 取消推荐 -> 不扣积分。
	code, body = callBusinessAPI(handler, http.MethodDelete, "/api/v1/admin/recommendations/"+postID, adminToken, nil, nil)
	if code != http.StatusOK {
		t.Fatalf("取消推荐应返回 200，实际 %d：%s", code, body)
	}
	if got := balanceOf(); got != initial+20 {
		t.Fatalf("取消推荐不应扣分，余额=%d, want %d", got, initial+20)
	}

	// 3. 再次上推荐 -> 同一帖子只发一次奖励。
	code, body = callBusinessAPI(handler, http.MethodPut, "/api/v1/admin/recommendations/"+postID, adminToken, nil, nil)
	if code != http.StatusOK {
		t.Fatalf("再次上推荐应返回 200，实际 %d：%s", code, body)
	}
	if got := balanceOf(); got != initial+20 {
		t.Fatalf("重复推荐不应重复加分，余额=%d, want %d", got, initial+20)
	}
	if got := recommendTxCount(); got != 1 {
		t.Fatalf("重复推荐后推荐流水=%d, want 1", got)
	}
}
