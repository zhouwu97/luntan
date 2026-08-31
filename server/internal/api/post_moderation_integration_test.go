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

	// 验证 GitHub 等普通链接在老账号或首帖下能正常发布为 published，不被误判为 pending
	oldUserSuffix := time.Now().UnixNano() + 1
	oldEmail := fmt.Sprintf("itest-old-%d@example.com", oldUserSuffix)
	oldUsername := fmt.Sprintf("itest_old_%d", oldUserSuffix%100000000)
	oldRegBody, _ := json.Marshal(map[string]string{"email": oldEmail, "code": devCode, "password": "password123", "nickname": "老用户", "username": oldUsername})
	oldRegReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(oldRegBody))
	oldRegRec := httptest.NewRecorder()
	handler.ServeHTTP(oldRegRec, oldRegReq)
	var oldRegResp map[string]any
	_ = json.Unmarshal(oldRegRec.Body.Bytes(), &oldRegResp)
	oldToken, _ := oldRegResp["access_token"].(string)
	oldUserID, _ := oldRegResp["user"].(map[string]any)["id"].(string)

	// 修改老用户注册时间为 48 小时前，模拟老账号
	if _, err := s.db.Exec(`UPDATE users SET created_at = now() - interval '48 hours' WHERE id = $1`, oldUserID); err != nil {
		t.Fatal(err)
	}

	// 老账号发布包含 https://github.com/ 的帖子
	urlPostBody, _ := json.Marshal(map[string]string{
		"title":        "GitHub链接分享",
		"content":      "推荐这个开源项目：https://github.com/example/repo 欢迎大家star！",
		"type":         "normal",
		"community_id": communityID,
	})
	urlReq := httptest.NewRequest(http.MethodPost, "/api/v1/posts", bytes.NewReader(urlPostBody))
	urlReq.Header.Set("Authorization", "Bearer "+oldToken)
	urlRec := httptest.NewRecorder()
	handler.ServeHTTP(urlRec, urlReq)
	if urlRec.Code != http.StatusCreated {
		t.Fatalf("url post failed: %d %s", urlRec.Code, urlRec.Body.String())
	}
	var urlResp map[string]any
	_ = json.Unmarshal(urlRec.Body.Bytes(), &urlResp)
	if urlResp["post_status"] != "published" || urlResp["moderation_status"] != "normal" {
		t.Fatalf("normal URL should be published and normal, got post_status=%v moderation_status=%v", urlResp["post_status"], urlResp["moderation_status"])
	}

	// 发布含有垃圾推广特征的内容，应当被送入 pending 审核
	spamPostBody, _ := json.Marshal(map[string]string{
		"title":        "加微信交流",
		"content":      "欢迎加微信：13800138000 拉群",
		"type":         "normal",
		"community_id": communityID,
	})
	spamReq := httptest.NewRequest(http.MethodPost, "/api/v1/posts", bytes.NewReader(spamPostBody))
	spamReq.Header.Set("Authorization", "Bearer "+oldToken)
	spamRec := httptest.NewRecorder()
	handler.ServeHTTP(spamRec, spamReq)
	if spamRec.Code != http.StatusCreated {
		t.Fatalf("spam post request failed: %d %s", spamRec.Code, spamRec.Body.String())
	}
	var spamResp map[string]any
	_ = json.Unmarshal(spamRec.Body.Bytes(), &spamResp)
	if spamResp["post_status"] != "pending" || spamResp["moderation_status"] != "pending" {
		t.Fatalf("spam post should be pending, got post_status=%v moderation_status=%v", spamResp["post_status"], spamResp["moderation_status"])
	}

	// 验证作者查看自己的个人中心 (/api/v1/profile/posts)，应包含 pending 的帖子，且携带 moderation_status: "pending"
	myPostsReq := httptest.NewRequest(http.MethodGet, "/api/v1/profile/posts", nil)
	myPostsReq.Header.Set("Authorization", "Bearer "+oldToken)
	myPostsRec := httptest.NewRecorder()
	handler.ServeHTTP(myPostsRec, myPostsReq)
	if myPostsRec.Code != http.StatusOK {
		t.Fatalf("get my posts failed: %d %s", myPostsRec.Code, myPostsRec.Body.String())
	}
	var myPostsResp map[string]any
	_ = json.Unmarshal(myPostsRec.Body.Bytes(), &myPostsResp)
	myItems, _ := myPostsResp["items"].([]any)
	if len(myItems) != 2 {
		t.Fatalf("author should see both normal and pending posts, got %d items", len(myItems))
	}

	// 验证访客查看他人用户主页 (/api/v1/users/:id/posts)，不应该看到 pending 帖子
	otherUserPostsReq := httptest.NewRequest(http.MethodGet, "/api/v1/users/"+oldUserID+"/posts", nil)
	otherUserPostsReq.Header.Set("Authorization", "Bearer "+token) // 另一个用户
	otherUserPostsRec := httptest.NewRecorder()
	handler.ServeHTTP(otherUserPostsRec, otherUserPostsReq)
	if otherUserPostsRec.Code != http.StatusOK {
		t.Fatalf("get other user posts failed: %d %s", otherUserPostsRec.Code, otherUserPostsRec.Body.String())
	}
	var otherUserPostsResp map[string]any
	_ = json.Unmarshal(otherUserPostsRec.Body.Bytes(), &otherUserPostsResp)
	otherItems, _ := otherUserPostsResp["items"].([]any)
	if len(otherItems) != 1 {
		t.Fatalf("visitor should only see published post, got %d items", len(otherItems))
	}
}
