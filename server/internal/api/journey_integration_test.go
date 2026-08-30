package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/outbox"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

// 登录→上传→发帖→Feed→评论→通知 的真实 Postgres 全链路验收：
// A 注册后走真实 HTTP 接口申请上传凭证并 complete 媒体、发布带图首帖；
// B 注册后密码登录，从 Feed 看到带图新帖，先根评论、再回复 A 的评论；
// A 通过通知接口收到 reply 通知；outbox Worker 把 media.process 等
// 事件全部消费成功并生成多级图片变体。未配置 DATABASE_URL 时跳过。
func TestPublishToNotificationJourneyAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	store := storage.NewMemoryStorage()
	handler := NewHandlerWithMedia(s.db, nil, store)
	ctx := context.Background()

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())

	// 社区仅作为发帖前置数据（社区管理不在本验收链路内）。
	categoryID := "journey-cat-" + suffix
	communityID := "journey-com-" + suffix
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, 'journey', $2)`, categoryID, "journey-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, 'journey', 'active')`, communityID, categoryID, "journey-com-"+suffix); err != nil {
		t.Fatal(err)
	}

	// 1. A 注册。
	author := registerViaAPI(t, handler, "journey_author_"+suffix, "旅程作者")

	// 2. A 申请上传凭证、上传字节并 complete。
	rawJPEG := createReal2400x1600JPEG()
	hasher := sha256.New()
	_, _ = hasher.Write(rawJPEG)
	rawHash := hex.EncodeToString(hasher.Sum(nil))

	tokenBody, _ := json.Marshal(map[string]any{
		"file_name": "journey.jpg",
		"mime_type": "image/jpeg",
		"width":     2400,
		"height":    1600,
		"size":      len(rawJPEG),
		"sha256":    rawHash,
	})
	tokenReq := httptest.NewRequest(http.MethodPost, "/api/v1/media/upload-token", bytes.NewReader(tokenBody))
	tokenReq.Header.Set("Authorization", "Bearer "+author.AccessToken)
	tokenRes := httptest.NewRecorder()
	handler.ServeHTTP(tokenRes, tokenReq)
	if tokenRes.Code != http.StatusCreated {
		t.Fatalf("upload-token: status=%d body=%s", tokenRes.Code, tokenRes.Body.String())
	}
	var token struct {
		MediaID   string `json:"media_id"`
		ObjectKey string `json:"object_key"`
	}
	if err := json.Unmarshal(tokenRes.Body.Bytes(), &token); err != nil {
		t.Fatal(err)
	}
	// MemoryStorage 的 memory:// 上传地址没有 HTTP 语义，这里等价模拟客户端
	// 把字节 PUT 到签名地址的动作。
	if err := store.Put(ctx, token.ObjectKey, "image/jpeg", bytes.NewReader(rawJPEG), int64(len(rawJPEG))); err != nil {
		t.Fatal(err)
	}
	completeBody, _ := json.Marshal(map[string]any{"size": len(rawJPEG), "sha256": rawHash})
	completeReq := httptest.NewRequest(http.MethodPost, "/api/v1/media/"+token.MediaID+"/complete", bytes.NewReader(completeBody))
	completeReq.Header.Set("Authorization", "Bearer "+author.AccessToken)
	completeRes := httptest.NewRecorder()
	handler.ServeHTTP(completeRes, completeReq)
	if completeRes.Code != http.StatusOK {
		t.Fatalf("media complete: status=%d body=%s", completeRes.Code, completeRes.Body.String())
	}

	// 3. A 发布带图首帖（新账号当日首帖会被反滥用触发器放行）。
	postBody, _ := json.Marshal(map[string]any{
		"community_id": communityID,
		"type":         "normal",
		"title":        "圣杯酱开箱：星野爱丽丝2代到货",
		"content":      "开箱图文一体测评，欢迎讨论。",
		"media_ids":    []string{token.MediaID},
	})
	postReq := httptest.NewRequest(http.MethodPost, "/api/v1/posts", bytes.NewReader(postBody))
	postReq.Header.Set("Authorization", "Bearer "+author.AccessToken)
	postReq.Header.Set("Idempotency-Key", "journey-post-"+suffix)
	postRes := httptest.NewRecorder()
	handler.ServeHTTP(postRes, postReq)
	if postRes.Code != http.StatusCreated {
		t.Fatalf("create post: status=%d body=%s", postRes.Code, postRes.Body.String())
	}
	var createdPost struct {
		ID         string   `json:"id"`
		PostStatus string   `json:"post_status"`
		MediaIDs   []string `json:"media_ids"`
	}
	if err := json.Unmarshal(postRes.Body.Bytes(), &createdPost); err != nil {
		t.Fatal(err)
	}
	if createdPost.PostStatus != "published" {
		t.Fatalf("expected first post published, got post_status=%q", createdPost.PostStatus)
	}
	if len(createdPost.MediaIDs) != 1 || createdPost.MediaIDs[0] != token.MediaID {
		t.Fatalf("expected media attached, got %v", createdPost.MediaIDs)
	}

	// 4. B 注册并用密码重新登录。
	commenter := registerViaAPI(t, handler, "journey_commenter_"+suffix, "旅程看客")
	loginBody, _ := json.Marshal(map[string]string{
		"username": "journey_commenter_" + suffix,
		"password": "安全密码12345",
	})
	loginReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", bytes.NewReader(loginBody))
	loginRes := httptest.NewRecorder()
	handler.ServeHTTP(loginRes, loginReq)
	if loginRes.Code != http.StatusOK {
		t.Fatalf("login: status=%d body=%s", loginRes.Code, loginRes.Body.String())
	}
	var login struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal(loginRes.Body.Bytes(), &login); err != nil {
		t.Fatal(err)
	}
	if login.AccessToken == "" {
		t.Fatal("login returned empty access_token")
	}

	// 5. B 从 Feed 看到带图新帖。
	feedReq := httptest.NewRequest(http.MethodGet, "/api/v1/feed/latest?community_id="+communityID, nil)
	feedRes := httptest.NewRecorder()
	handler.ServeHTTP(feedRes, feedReq)
	if feedRes.Code != http.StatusOK {
		t.Fatalf("feed: status=%d body=%s", feedRes.Code, feedRes.Body.String())
	}
	var feed struct {
		Items []struct {
			ID    string                   `json:"id"`
			Media []map[string]interface{} `json:"media"`
		} `json:"items"`
	}
	if err := json.Unmarshal(feedRes.Body.Bytes(), &feed); err != nil {
		t.Fatal(err)
	}
	feedHit := false
	for _, item := range feed.Items {
		if item.ID == createdPost.ID && len(item.Media) > 0 {
			feedHit = true
		}
	}
	if !feedHit {
		t.Fatalf("feed missing journey post with media: %s", feedRes.Body.String())
	}

	// 6. 评论链路：A 先在自己帖下留根评论，B 根评论后再回复 A 的根评论。
	authorCommentID := createCommentViaAPI(t, handler, author.AccessToken, createdPost.ID, "作者补充：配件清单见图三。", suffix+"-author")
	createCommentViaAPI(t, handler, login.AccessToken, createdPost.ID, "坐等测评结论。", suffix+"-b-root")
	replyBody, _ := json.Marshal(map[string]any{"content": "结论就是闭眼冲，求优惠码？"})
	replyReq := httptest.NewRequest(http.MethodPost, "/api/v1/comments/"+authorCommentID+"/replies", bytes.NewReader(replyBody))
	replyReq.Header.Set("Authorization", "Bearer "+login.AccessToken)
	replyReq.Header.Set("Idempotency-Key", "journey-reply-"+suffix)
	replyRes := httptest.NewRecorder()
	handler.ServeHTTP(replyRes, replyReq)
	if replyRes.Code != http.StatusCreated {
		t.Fatalf("reply: status=%d body=%s", replyRes.Code, replyRes.Body.String())
	}

	// 7. A 收到 reply 通知且未读数 +1。
	notifReq := httptest.NewRequest(http.MethodGet, "/api/v1/notifications?limit=50", nil)
	notifReq.Header.Set("Authorization", "Bearer "+author.AccessToken)
	notifRes := httptest.NewRecorder()
	handler.ServeHTTP(notifRes, notifReq)
	if notifRes.Code != http.StatusOK {
		t.Fatalf("notifications: status=%d body=%s", notifRes.Code, notifRes.Body.String())
	}
	var notifList struct {
		Items []struct {
			Type     string `json:"type"`
			Actor    struct {
				ID string `json:"id"`
			} `json:"actor"`
			TargetID string `json:"target_id"`
			IsRead   bool   `json:"is_read"`
		} `json:"items"`
	}
	if err := json.Unmarshal(notifRes.Body.Bytes(), &notifList); err != nil {
		t.Fatal(err)
	}
	replyNotified := false
	for _, item := range notifList.Items {
		if item.Type == "reply" && item.Actor.ID == commenter.ID && item.TargetID == createdPost.ID && !item.IsRead {
			replyNotified = true
		}
	}
	if !replyNotified {
		t.Fatalf("author did not receive unread reply notification: %s", notifRes.Body.String())
	}
	unreadReq := httptest.NewRequest(http.MethodGet, "/api/v1/notifications/unread-count", nil)
	unreadReq.Header.Set("Authorization", "Bearer "+author.AccessToken)
	unreadRes := httptest.NewRecorder()
	handler.ServeHTTP(unreadRes, unreadReq)
	if unreadRes.Code != http.StatusOK {
		t.Fatalf("unread-count: status=%d body=%s", unreadRes.Code, unreadRes.Body.String())
	}
	var unread struct {
		UnreadCount int64 `json:"unread_count"`
	}
	if err := json.Unmarshal(unreadRes.Body.Bytes(), &unread); err != nil {
		t.Fatal(err)
	}
	if unread.UnreadCount < 1 {
		t.Fatalf("expected unread_count >= 1, got %d", unread.UnreadCount)
	}

	// 8. outbox Worker 消费闭环：media.process 生成多级变体，其余事件走 Noop。
	router := outbox.NewRouterHandler()
	router.Register("media.process", outbox.MediaHandler{DB: s.db, Storage: store})
	router.SetFallback(outbox.NoopHandler{})
	worker := outbox.Worker{DB: s.db, Handler: router, BatchSize: 100}
	if _, err := worker.RunOnce(ctx); err != nil {
		t.Fatalf("outbox worker: %v", err)
	}
	var mediaEventStatus string
	if err := s.db.QueryRow(
		`SELECT status FROM outbox_events WHERE aggregate_id = $1 AND event_type = 'media.process' ORDER BY created_at DESC LIMIT 1`,
		token.MediaID,
	).Scan(&mediaEventStatus); err != nil {
		t.Fatal(err)
	}
	if mediaEventStatus != "succeeded" {
		t.Fatalf("media.process event status=%s, want succeeded", mediaEventStatus)
	}
	for _, variantKey := range []string{
		token.ObjectKey + "_thumb.jpg",
		token.ObjectKey + "_detail.jpg",
		token.ObjectKey + "_original.jpg",
	} {
		if _, ok := store.GetBytes(variantKey); !ok {
			t.Fatalf("storage missing generated variant %s", variantKey)
		}
	}
}

type journeyUser struct {
	ID          string
	AccessToken string
}

func registerViaAPI(t *testing.T, handler http.Handler, username, nickname string) journeyUser {
	t.Helper()
	body, _ := json.Marshal(map[string]string{
		"username": username,
		"password": "安全密码12345",
		"nickname": nickname,
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusCreated {
		t.Fatalf("register %s: status=%d body=%s", username, res.Code, res.Body.String())
	}
	var session struct {
		AccessToken string `json:"access_token"`
		User        struct {
			ID string `json:"id"`
		} `json:"user"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	if session.AccessToken == "" || session.User.ID == "" {
		t.Fatalf("register response missing token/user: %s", res.Body.String())
	}
	return journeyUser{ID: session.User.ID, AccessToken: session.AccessToken}
}

func createCommentViaAPI(t *testing.T, handler http.Handler, token, postID, content, keySuffix string) string {
	t.Helper()
	body, _ := json.Marshal(map[string]string{"content": content})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts/"+postID+"/comments", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Idempotency-Key", "journey-cmt-"+keySuffix)
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusCreated {
		t.Fatalf("create comment: status=%d body=%s", res.Code, res.Body.String())
	}
	var created struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	if created.ID == "" {
		t.Fatalf("empty comment id in response: %s", res.Body.String())
	}
	return created.ID
}
