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

// 新账号反滥用触发器（apply_forum_content_rules）与 API 响应必须一致：
// 新账号当日第 2 帖由 DB 触发器置为 pending，响应不得声称 published。
func TestCreatePostResponseReflectsModerationTrigger(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)

	suffix := time.Now().UnixNano()
	email := fmt.Sprintf("itest-mod-%d@example.com", suffix)
	username := fmt.Sprintf("itest_mod_%d", suffix%100000000)

	codeBody, _ := json.Marshal(map[string]string{"email": email, "purpose": "register"})
	codeReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/code/request", bytes.NewReader(codeBody))
	codeRec := httptest.NewRecorder()
	handler.ServeHTTP(codeRec, codeReq)
	var codeResp map[string]any
	_ = json.Unmarshal(codeRec.Body.Bytes(), &codeResp)
	devCode, _ := codeResp["dev_code"].(string)
	if devCode == "" {
		t.Fatalf("dev_code missing: %s", codeRec.Body.String())
	}
	regBody, _ := json.Marshal(map[string]string{"email": email, "code": devCode, "password": "password123", "nickname": "验收审核", "username": username})
	regReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(regBody))
	regRec := httptest.NewRecorder()
	handler.ServeHTTP(regRec, regReq)
	if regRec.Code != http.StatusCreated {
		t.Fatalf("register failed: %d %s", regRec.Code, regRec.Body.String())
	}
	var regResp map[string]any
	_ = json.Unmarshal(regRec.Body.Bytes(), &regResp)
	token, _ := regResp["access_token"].(string)
	if token == "" {
		t.Fatalf("missing access_token")
	}

	categoryID := fmt.Sprintf("itest-mod-cat-%d", suffix)
	communityID := fmt.Sprintf("itest-mod-com-%d", suffix)
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, $2, $3)`, categoryID, "itest", "itest-mod-"+fmt.Sprint(suffix%100000)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, $4, 'active')`, communityID, categoryID, communityID, "itest"); err != nil {
		t.Fatal(err)
	}

	postBody := func(n int) []byte {
		b, _ := json.Marshal(map[string]string{"title": fmt.Sprintf("审核一致性帖%d %d", n, suffix), "content": "普通内容,无外链", "type": "normal", "community_id": communityID})
		return b
	}

	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/posts", bytes.NewReader(postBody(1)))
	req1.Header.Set("Idempotency-Key", fmt.Sprintf("itest-mod-1-%d", suffix))
	req1.Header.Set("Authorization", "Bearer "+token)
	rec1 := httptest.NewRecorder()
	handler.ServeHTTP(rec1, req1)
	if rec1.Code != http.StatusCreated {
		t.Fatalf("first post failed: %d %s", rec1.Code, rec1.Body.String())
	}
	var resp1 map[string]any
	_ = json.Unmarshal(rec1.Body.Bytes(), &resp1)
	if resp1["post_status"] != "published" {
		t.Fatalf("first post of the day should be published, got %v", resp1["post_status"])
	}

	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/posts", bytes.NewReader(postBody(2)))
	req2.Header.Set("Idempotency-Key", fmt.Sprintf("itest-mod-2-%d", suffix))
	req2.Header.Set("Authorization", "Bearer "+token)
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusCreated {
		t.Fatalf("second post failed: %d %s", rec2.Code, rec2.Body.String())
	}
	var resp2 map[string]any
	_ = json.Unmarshal(rec2.Body.Bytes(), &resp2)
	postID, _ := resp2["id"].(string)
	var dbStatus string
	if err := s.db.QueryRow(`SELECT post_status FROM posts WHERE id = $1`, postID).Scan(&dbStatus); err != nil {
		t.Fatal(err)
	}
	if resp2["post_status"] != dbStatus {
		t.Fatalf("API post_status=%v 与数据库 post_status=%s 不一致", resp2["post_status"], dbStatus)
	}
	if dbStatus != "pending" {
		t.Fatalf("new account second post of the day should be pending in DB, got %s", dbStatus)
	}
}
