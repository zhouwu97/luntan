package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

func rankingSubmissionTestUser(t *testing.T, s *Server, handler http.Handler, tag string) (email, username, token string) {
	t.Helper()
	suffix := time.Now().UnixNano()
	email = fmt.Sprintf("itest-sub-%s-%d@example.com", tag, suffix)
	username = fmt.Sprintf("itest_sub_%s_%d", tag, suffix%100000000)
	token = registerAndLogin(t, handler, email, username, "password123")
	return email, username, token
}

func promoteRoleByEmail(t *testing.T, s *Server, email, roleName string) {
	t.Helper()
	var userID, roleID string
	if err := s.db.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, email).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := s.db.QueryRow(`SELECT id FROM roles WHERE name = $1`, roleName).Scan(&roleID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO user_roles (id, user_id, role_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
		"ur-"+userID+"-"+roleID, userID, roleID); err != nil {
		t.Fatal(err)
	}
}

func rankingToyNames(t *testing.T, handler http.Handler) []string {
	t.Helper()
	code, body := callBusinessAPI(handler, http.MethodGet, "/api/v1/ranking/toys", "", nil, nil)
	if code != http.StatusOK {
		t.Fatalf("GET /ranking/toys 应返回 200，实际 %d：%s", code, body)
	}
	var payload struct {
		Items []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"items"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		t.Fatal(err)
	}
	names := make([]string, 0, len(payload.Items))
	for _, item := range payload.Items {
		names = append(names, item.Name)
	}
	return names
}

func rankingToyIDs(t *testing.T, handler http.Handler) []string {
	t.Helper()
	code, body := callBusinessAPI(handler, http.MethodGet, "/api/v1/ranking/toys", "", nil, nil)
	if code != http.StatusOK {
		t.Fatalf("GET /ranking/toys 应返回 200，实际 %d：%s", code, body)
	}
	var payload struct {
		Items []struct {
			ID string `json:"id"`
		} `json:"items"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		t.Fatal(err)
	}
	ids := make([]string, 0, len(payload.Items))
	for _, item := range payload.Items {
		ids = append(ids, item.ID)
	}
	return ids
}

// 未登录提交 401；合法提交 201 且 pending 不出现在综合热榜；非法字段 400。
func TestRankingToySubmissionCreateAndValidate(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)
	_, _, token := rankingSubmissionTestUser(t, s, handler, "basic")
	uniqueName := fmt.Sprintf("投稿测试杯 %d", time.Now().UnixNano())

	// 未登录
	code, body := callBusinessAPI(handler, http.MethodPost, "/api/v1/ranking/submissions", "", map[string]any{"name": "x", "category": "cup"}, nil)
	if code != http.StatusUnauthorized {
		t.Fatalf("未登录提交应返回 401，实际 %d：%s", code, body)
	}

	// 合法提交
	code, body = callBusinessAPI(handler, http.MethodPost, "/api/v1/ranking/submissions", token, map[string]any{"name": uniqueName, "category": "cup"}, nil)
	if code != http.StatusCreated {
		t.Fatalf("合法提交应返回 201，实际 %d：%s", code, body)
	}
	var created struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	}
	if err := json.Unmarshal(body, &created); err != nil {
		t.Fatal(err)
	}
	if created.ID == "" || created.Status != "pending" {
		t.Fatalf("提交响应异常：%s", body)
	}
	for _, name := range rankingToyNames(t, handler) {
		if name == uniqueName {
			t.Fatal("pending 投稿不应出现在综合热榜")
		}
	}

	// name 为空
	code, _ = callBusinessAPI(handler, http.MethodPost, "/api/v1/ranking/submissions", token, map[string]any{"name": "  ", "category": "cup"}, nil)
	if code != http.StatusBadRequest {
		t.Fatalf("空名称应返回 400，实际 %d", code)
	}

	// 品类大小写敏感：前端大写键必须被拒绝
	code, _ = callBusinessAPI(handler, http.MethodPost, "/api/v1/ranking/submissions", token, map[string]any{"name": "大小写", "category": "CUP"}, nil)
	if code != http.StatusBadRequest {
		t.Fatalf("大写品类应返回 400，实际 %d", code)
	}

	// 封面非本人
	otherID := fmt.Sprintf("itest-cover-owner-%d", time.Now().UnixNano())
	otherUsername := fmt.Sprintf("itest_cover_owner_%d", time.Now().UnixNano())
	if _, err := s.db.Exec(`INSERT INTO users (id, username, status) VALUES ($1, $2, 'active')`, otherID, otherUsername); err != nil {
		t.Fatal(err)
	}
	mediaID := fmt.Sprintf("itest-media-%d", time.Now().UnixNano())
	if _, err := s.db.Exec(`INSERT INTO media_assets (id, owner_id, object_key, original_name, mime_type, size, status) VALUES ($1, $2, $3, 'cover.png', 'image/png', 100, 'ready')`,
		mediaID, otherID, "itest/cover/"+mediaID+".png"); err != nil {
		t.Fatal(err)
	}
	code, _ = callBusinessAPI(handler, http.MethodPost, "/api/v1/ranking/submissions", token, map[string]any{"name": "借用封面", "category": "cup", "cover_media_id": mediaID}, nil)
	if code != http.StatusBadRequest {
		t.Fatalf("他人封面应返回 400，实际 %d", code)
	}
}

// 同一用户最多 5 条 pending，第 6 条返回 SUBMISSION_LIMIT。
func TestRankingToySubmissionLimit(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)
	_, _, token := rankingSubmissionTestUser(t, s, handler, "limit")
	for i := 0; i < 5; i++ {
		code, body := callBusinessAPI(handler, http.MethodPost, "/api/v1/ranking/submissions", token, map[string]any{"name": fmt.Sprintf("灌水测试 %d %d", i, time.Now().UnixNano()), "category": "lubricant"}, nil)
		if code != http.StatusCreated {
			t.Fatalf("第 %d 条提交应成功，实际 %d：%s", i+1, code, body)
		}
	}
	code, body := callBusinessAPI(handler, http.MethodPost, "/api/v1/ranking/submissions", token, map[string]any{"name": "第六条", "category": "cup"}, nil)
	if code != http.StatusBadRequest {
		t.Fatalf("第 6 条 pending 应返回 400，实际 %d：%s", code, body)
	}
	if !strings.Contains(string(body), "SUBMISSION_LIMIT") {
		t.Fatalf("应返回 SUBMISSION_LIMIT：%s", body)
	}
}

// 普通管理员（platform_moderator）无审核权：list/review/reorder 全部 403。
func TestRankingSubmissionModeratorForbidden(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)
	moderatorEmail, _, moderatorToken := rankingSubmissionTestUser(t, s, handler, "mod")
	promoteRoleByEmail(t, s, moderatorEmail, "platform_moderator")

	code, body := callBusinessAPI(handler, http.MethodGet, "/api/v1/admin/ranking/submissions", moderatorToken, nil, nil)
	if code != http.StatusForbidden {
		t.Fatalf("普通管理员读取投稿列表应返回 403，实际 %d：%s", code, body)
	}
	code, body = callBusinessAPI(handler, http.MethodPost, "/api/v1/admin/ranking/submissions/some-id/review", moderatorToken, map[string]any{"action": "approve"}, nil)
	if code != http.StatusForbidden {
		t.Fatalf("普通管理员审核应返回 403，实际 %d：%s", code, body)
	}
	code, body = callBusinessAPI(handler, http.MethodPut, "/api/v1/admin/ranking/reorder", moderatorToken, map[string]any{"toy_ids": []string{"toy-butter-2"}}, nil)
	if code != http.StatusForbidden {
		t.Fatalf("普通管理员调序应返回 403，实际 %d：%s", code, body)
	}
}

// 超管审核闭环：list 带 submitter.nickname；approve 后出现在榜单末尾且不可重复审核；
// reject 后不出现在榜单、note 回显。
func TestRankingSubmissionReviewBySuperAdmin(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)
	submitterEmail, _, submitterToken := rankingSubmissionTestUser(t, s, handler, "review")
	superEmail, _, superToken := rankingSubmissionTestUser(t, s, handler, "super")
	promoteSuperAdmin(t, s, superEmail)
	superToken = loginUser(t, handler, superEmail, "password123")

	var submitterID, submitterUsername string
	if err := s.db.QueryRow(`SELECT id, username FROM users WHERE lower(email) = $1`, submitterEmail).Scan(&submitterID, &submitterUsername); err != nil {
		t.Fatal(err)
	}
	nickname := fmt.Sprintf("投稿达人%d", time.Now().UnixNano()%1000000)
	if _, err := s.db.Exec(`INSERT INTO user_profiles (user_id, nickname) VALUES ($1, $2) ON CONFLICT (user_id) DO UPDATE SET nickname = EXCLUDED.nickname`, submitterID, nickname); err != nil {
		t.Fatal(err)
	}

	approveName := fmt.Sprintf("审核通过杯 %d", time.Now().UnixNano())
	rejectName := fmt.Sprintf("审核驳回杯 %d", time.Now().UnixNano())
	submitOne := func(name, category string) string {
		code, body := callBusinessAPI(handler, http.MethodPost, "/api/v1/ranking/submissions", submitterToken, map[string]any{"name": name, "category": category, "merchant": "测试品牌", "description": "介绍"}, nil)
		if code != http.StatusCreated {
			t.Fatalf("提交 %s 应成功，实际 %d：%s", name, code, body)
		}
		var created struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(body, &created); err != nil {
			t.Fatal(err)
		}
		return created.ID
	}
	approveID := submitOne(approveName, "small_hip")
	rejectID := submitOne(rejectName, "cup")

	// list 默认 pending，带 submitter.nickname
	code, body := callBusinessAPI(handler, http.MethodGet, "/api/v1/admin/ranking/submissions", superToken, nil, nil)
	if code != http.StatusOK {
		t.Fatalf("超管读取投稿列表应返回 200，实际 %d：%s", code, body)
	}
	var listPayload struct {
		Items []struct {
			ID        string `json:"id"`
			Name      string `json:"name"`
			Category  string `json:"category"`
			Submitter struct {
				ID       string `json:"id"`
				Username string `json:"username"`
				Nickname string `json:"nickname"`
			} `json:"submitter"`
		} `json:"items"`
	}
	if err := json.Unmarshal(body, &listPayload); err != nil {
		t.Fatal(err)
	}
	foundSubmitter := false
	for _, item := range listPayload.Items {
		if item.ID == approveID {
			if item.Submitter.ID != submitterID || item.Submitter.Nickname != nickname || item.Submitter.Username != submitterUsername {
				t.Fatalf("submitter 信息异常：%+v", item.Submitter)
			}
			foundSubmitter = true
		}
	}
	if !foundSubmitter {
		t.Fatal("pending 列表缺少刚提交的投稿")
	}

	// approve → 榜单末尾出现该玩具
	code, body = callBusinessAPI(handler, http.MethodPost, "/api/v1/admin/ranking/submissions/"+approveID+"/review", superToken, map[string]any{"action": "approve"}, nil)
	if code != http.StatusOK {
		t.Fatalf("审核通过应返回 200，实际 %d：%s", code, body)
	}
	names := rankingToyNames(t, handler)
	if len(names) == 0 || names[len(names)-1] != approveName {
		t.Fatalf("通过后玩具应出现在综合热榜末尾，实际末尾：%v", names)
	}

	// 重复审核同条 → 409
	code, body = callBusinessAPI(handler, http.MethodPost, "/api/v1/admin/ranking/submissions/"+approveID+"/review", superToken, map[string]any{"action": "approve"}, nil)
	if code != http.StatusConflict {
		t.Fatalf("重复审核应返回 409，实际 %d：%s", code, body)
	}

	// reject → 不上榜，note 回显
	code, body = callBusinessAPI(handler, http.MethodPost, "/api/v1/admin/ranking/submissions/"+rejectID+"/review", superToken, map[string]any{"action": "reject", "note": "信息不完整"}, nil)
	if code != http.StatusOK {
		t.Fatalf("驳回应返回 200，实际 %d：%s", code, body)
	}
	for _, name := range rankingToyNames(t, handler) {
		if name == rejectName {
			t.Fatal("被驳回的投稿不应出现在榜单")
		}
	}
	code, body = callBusinessAPI(handler, http.MethodGet, "/api/v1/admin/ranking/submissions?status=rejected", superToken, nil, nil)
	if code != http.StatusOK {
		t.Fatalf("读取 rejected 列表应返回 200，实际 %d：%s", code, body)
	}
	var rejectedPayload struct {
		Items []struct {
			ID         string `json:"id"`
			Status     string `json:"status"`
			ReviewNote string `json:"review_note"`
		} `json:"items"`
	}
	if err := json.Unmarshal(body, &rejectedPayload); err != nil {
		t.Fatal(err)
	}
	foundNote := false
	for _, item := range rejectedPayload.Items {
		if item.ID == rejectID {
			if item.ReviewNote != "信息不完整" {
				t.Fatalf("review_note 应回显，实际：%s", item.ReviewNote)
			}
			foundNote = true
		}
	}
	if !foundNote {
		t.Fatal("rejected 列表缺少被驳回的投稿")
	}
}

// 超管拖拽调序：第 2 名拖到第 5 名后顺序正确；子集/重复 id 返回 409。
func TestRankingReorderBySuperAdmin(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)
	superEmail, _, superToken := rankingSubmissionTestUser(t, s, handler, "reorder")
	promoteSuperAdmin(t, s, superEmail)
	superToken = loginUser(t, handler, superEmail, "password123")

	before := rankingToyIDs(t, handler)
	if len(before) < 5 {
		t.Fatalf("榜单玩具不足 5 个：%d", len(before))
	}
	reordered := make([]string, 0, len(before))
	reordered = append(reordered, before[0], before[2], before[3], before[4], before[1])
	reordered = append(reordered, before[5:]...)

	code, body := callBusinessAPI(handler, http.MethodPut, "/api/v1/admin/ranking/reorder", superToken, map[string]any{"toy_ids": reordered}, nil)
	if code != http.StatusOK {
		t.Fatalf("调序应返回 200，实际 %d：%s", code, body)
	}
	after := rankingToyIDs(t, handler)
	if len(after) != len(reordered) {
		t.Fatalf("调序后数量变化：%d -> %d", len(before), len(after))
	}
	for i := range reordered {
		if after[i] != reordered[i] {
			t.Fatalf("调序后顺序错误：位置 %d 期望 %s 实际 %s", i, reordered[i], after[i])
		}
	}

	// 子集 → 409
	code, _ = callBusinessAPI(handler, http.MethodPut, "/api/v1/admin/ranking/reorder", superToken, map[string]any{"toy_ids": after[:2]}, nil)
	if code != http.StatusConflict {
		t.Fatalf("子集调序应返回 409，实际 %d", code)
	}

	// 重复 id → 409
	duplicated := append([]string{}, after...)
	duplicated[1] = duplicated[0]
	code, _ = callBusinessAPI(handler, http.MethodPut, "/api/v1/admin/ranking/reorder", superToken, map[string]any{"toy_ids": duplicated}, nil)
	if code != http.StatusConflict {
		t.Fatalf("重复 id 调序应返回 409，实际 %d", code)
	}
}
