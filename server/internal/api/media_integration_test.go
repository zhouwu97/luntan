package api

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
)

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
