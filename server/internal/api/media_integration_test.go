package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"image"
	"image/jpeg"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

// TestCompleteMediaEmitsSingleOutboxEventAgainstPostgres 用真实事务并发验证：
// 只有成功把 pending 改成 ready 的请求可以发出 media.process 事件。
func TestCompleteMediaEmitsSingleOutboxEventAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "media_race_owner_" + suffix,
		Password: "安全密码12345",
		Nickname: "媒体并发测试",
	}, auth.SessionMetadata{UserAgent: "media-concurrency-integration-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	var raw bytes.Buffer
	if err := jpeg.Encode(&raw, image.NewRGBA(image.Rect(0, 0, 2, 2)), nil); err != nil {
		t.Fatal(err)
	}
	rawBytes := raw.Bytes()
	digest := sha256.Sum256(rawBytes)
	digestHex := hex.EncodeToString(digest[:])
	mediaID := "media-race-asset-" + suffix
	objectKey := "media/" + session.User.ID + "/" + mediaID
	store := storage.NewMemoryStorage()
	if err := store.Put(context.Background(), objectKey, "image/jpeg", bytes.NewReader(rawBytes), int64(len(rawBytes))); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`
		INSERT INTO media_assets (id, owner_id, object_key, original_name, mime_type,
			size, sha256, status, created_at, updated_at)
		VALUES ($1, $2, $3, 'race.jpg', 'image/jpeg', $4, $5, 'pending', now(), now())`,
		mediaID, session.User.ID, objectKey, len(rawBytes), digestHex); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = s.db.Exec(`DELETE FROM outbox_events WHERE aggregate_type = 'media' AND aggregate_id = $1 AND event_type = 'media.process'`, mediaID)
		_, _ = s.db.Exec(`DELETE FROM media_assets WHERE id = $1`, mediaID)
	})

	server := &Server{db: s.db, mediaStorage: store}
	start := make(chan struct{})
	responses := make(chan int, 2)
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			req := httptest.NewRequest(http.MethodPost, "/api/v1/media/"+mediaID+"/complete", nil)
			req = req.WithContext(context.WithValue(req.Context(), authenticatedUserContextKey{}, auth.User{ID: session.User.ID, AccountType: "email"}))
			res := httptest.NewRecorder()
			server.completeMedia(res, req, mediaID)
			responses <- res.Code
		}()
	}
	close(start)
	wg.Wait()
	close(responses)
	for status := range responses {
		if status != http.StatusOK {
			t.Fatalf("concurrent complete status=%d, want 200", status)
		}
	}

	var readyCount, outboxCount int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM media_assets WHERE id = $1 AND status = 'ready'`, mediaID).Scan(&readyCount); err != nil {
		t.Fatal(err)
	}
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM outbox_events WHERE aggregate_type = 'media' AND aggregate_id = $1 AND event_type = 'media.process'`, mediaID).Scan(&outboxCount); err != nil {
		t.Fatal(err)
	}
	if readyCount != 1 || outboxCount != 1 {
		t.Fatalf("concurrent complete persisted ready=%d outbox=%d, want 1/1", readyCount, outboxCount)
	}
}

func TestDeleteMediaRejectsAssetAttachedToPostAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "media_owner_" + suffix,
		Password: "安全密码12345",
		Nickname: "媒体测试",
	}, auth.SessionMetadata{UserAgent: "media-integration-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	categoryID := "media-cat-" + suffix
	communityID := "media-community-" + suffix
	postID := "media-post-" + suffix
	mediaID := "media-asset-" + suffix
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, 'media', $2)`, categoryID, "media-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, 'media', 'active')`, communityID, categoryID, "media-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at) VALUES ($1, $2, $3, 'normal', 'published', 'normal', 'media', 'media', now())`, postID, session.User.ID, communityID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO media_assets (id, owner_id, object_key, original_name, mime_type, size, sha256, status, completed_at) VALUES ($1, $2, $3, 'a.png', 'image/png', 10, $4, 'ready', now())`, mediaID, session.User.ID, "media/"+session.User.ID+"/"+mediaID, strings.Repeat("a", 64)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO post_media (post_id, media_id) VALUES ($1, $2)`, postID, mediaID); err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/media/"+mediaID, nil)
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	res := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(res, req)

	if res.Code != http.StatusConflict || !strings.Contains(res.Body.String(), `"code":"MEDIA_IN_USE"`) {
		t.Fatalf("delete attached media: status=%d body=%s", res.Code, res.Body.String())
	}
}

// 评论附件引用的媒体不允许被绕过业务直接删除，否则评论图片会静默消失。
func TestDeleteMediaRejectsAssetAttachedToCommentAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "comment_media_owner_" + suffix,
		Password: "安全密码12345",
		Nickname: "评论媒体测试",
	}, auth.SessionMetadata{UserAgent: "media-integration-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	categoryID := "comment-media-cat-" + suffix
	communityID := "comment-media-community-" + suffix
	postID := "comment-media-post-" + suffix
	commentID := "comment-media-comment-" + suffix
	mediaID := "comment-media-asset-" + suffix
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, 'media', $2)`, categoryID, "comment-media-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, 'media', 'active')`, communityID, categoryID, "comment-media-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at) VALUES ($1, $2, $3, 'normal', 'published', 'normal', 'media', 'media', now())`, postID, session.User.ID, communityID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`
		INSERT INTO comments (id, post_id, author_id, root_id, parent_id, content,
			publication_status, moderation_status, created_at, updated_at, published_at)
		VALUES ($1, $2, $3, $1, NULL, '带图回复', 'published', 'normal', now(), now(), now())`, commentID, postID, session.User.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO media_assets (id, owner_id, object_key, original_name, mime_type, size, sha256, status, completed_at) VALUES ($1, $2, $3, 'a.png', 'image/png', 10, $4, 'ready', now())`, mediaID, session.User.ID, "media/"+session.User.ID+"/"+mediaID, strings.Repeat("a", 64)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO comment_media (comment_id, media_id) VALUES ($1, $2)`, commentID, mediaID); err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/media/"+mediaID, nil)
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	res := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(res, req)

	if res.Code != http.StatusConflict || !strings.Contains(res.Body.String(), `"code":"MEDIA_IN_USE"`) {
		t.Fatalf("delete comment-attached media: status=%d body=%s", res.Code, res.Body.String())
	}
}

// 排行榜投稿封面引用的媒体同样受删除保护。
func TestDeleteMediaRejectsRankingSubmissionCoverAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "ranking_cover_owner_" + suffix,
		Password: "安全密码12345",
		Nickname: "投稿封面测试",
	}, auth.SessionMetadata{UserAgent: "media-integration-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	mediaID := "ranking-cover-asset-" + suffix
	submissionID := "ranking-cover-submission-" + suffix
	if _, err := s.db.Exec(`INSERT INTO media_assets (id, owner_id, object_key, original_name, mime_type, size, sha256, status, completed_at) VALUES ($1, $2, $3, 'cover.png', 'image/png', 10, $4, 'ready', now())`, mediaID, session.User.ID, "media/"+session.User.ID+"/"+mediaID, strings.Repeat("a", 64)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO ranking_toy_submissions (id, submitter_id, name, category, cover_media_id) VALUES ($1, $2, '测试玩具', 'cup', $3)`, submissionID, session.User.ID, mediaID); err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/media/"+mediaID, nil)
	req.Header.Set("Authorization", "Bearer "+session.AccessToken)
	res := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(res, req)

	if res.Code != http.StatusConflict || !strings.Contains(res.Body.String(), `"code":"MEDIA_IN_USE"`) {
		t.Fatalf("delete submission-cover media: status=%d body=%s", res.Code, res.Body.String())
	}
}
