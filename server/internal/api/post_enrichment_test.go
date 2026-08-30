package api

import (
	"net/http/httptest"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestPublicMediaURLKeepsAbsoluteImportedURL(t *testing.T) {
	t.Setenv("OBJECT_STORAGE_PUBLIC_BASE_URL", "http://example.test/imported-media")

	if got := publicMediaURL("http://example.test/imported-media/post.webp"); got != "http://example.test/imported-media/post.webp" {
		t.Fatalf("完整 URL 不应重复拼接公开前缀，得到 %q", got)
	}
	if got := publicMediaURL("ranking/beiyoujiang/cover.webp"); got != "http://example.test/imported-media/ranking/beiyoujiang/cover.webp" {
		t.Fatalf("相对对象键应拼接公开前缀，得到 %q", got)
	}
}

func TestPublicMediaURLUpgradesLegacyAbsoluteMediaURL(t *testing.T) {
	t.Setenv("OBJECT_STORAGE_PUBLIC_BASE_URL", "https://shengbeijiang.com/imported-media/user-media")

	if got := publicMediaURL("http://43.161.249.91/imported-media/post.webp"); got != "https://shengbeijiang.com/imported-media/post.webp" {
		t.Fatalf("旧媒体 URL 应升级到 HTTPS 正式域名，得到 %q", got)
	}
	if got := publicMediaURL("http://43.161.249.91/api/v1/media-file/media-1"); got != "https://shengbeijiang.com/api/v1/media-file/media-1" {
		t.Fatalf("API 兜底媒体 URL 应升级到 HTTPS 正式域名，得到 %q", got)
	}
	if got := publicMediaURL("http://images.example.com/photos/post.webp"); got != "http://images.example.com/photos/post.webp" {
		t.Fatalf("外部媒体 URL 不应被改写，得到 %q", got)
	}
}

func TestEnrichPostResponsePopulatesAuthorAvatar(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	server := &Server{db: db}
	post := &postResponse{
		ID:     "p-100",
		Author: userSummary{ID: "u-author", Username: "author1"},
	}

	mock.ExpectQuery(`SELECT ma\.id, ma\.mime_type`).
		WithArgs("p-100").
		WillReturnRows(sqlmock.NewRows([]string{"id", "mime_type", "width", "height", "original_name", "object_key"}))

	mock.ExpectQuery(`SELECT CASE WHEN u\.account_type = 'guest' THEN 0 ELSE COALESCE\(up\.level, 1\) END`).
		WithArgs("u-author").
		WillReturnRows(sqlmock.NewRows([]string{"level", "avatar_media_id", "object_key"}).
			AddRow(3, "m-avatar-1", "media/users/u-author/avatar.webp"))

	req := httptest.NewRequest("GET", "/api/v1/posts/p-100?include_details=1", nil)
	if err := server.enrichPostResponse(req.Context(), req, post, false); err != nil {
		t.Fatalf("enrichPostResponse error: %v", err)
	}

	if post.Author.Level != 3 {
		t.Errorf("expected Author.Level=3, got %d", post.Author.Level)
	}
	if post.Author.AvatarMediaID != "m-avatar-1" {
		t.Errorf("expected Author.AvatarMediaID=m-avatar-1, got %q", post.Author.AvatarMediaID)
	}
	if post.Author.AvatarURL != "/api/v1/media-file/media/users/u-author/avatar.webp" {
		t.Errorf("expected Author.AvatarURL=/api/v1/media-file/media/users/u-author/avatar.webp, got %q", post.Author.AvatarURL)
	}
}
