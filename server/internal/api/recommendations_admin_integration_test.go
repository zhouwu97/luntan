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
