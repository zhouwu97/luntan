package api

import "testing"

func TestPublicMediaURLKeepsAbsoluteImportedURL(t *testing.T) {
	t.Setenv("OBJECT_STORAGE_PUBLIC_BASE_URL", "http://example.test/imported-media")

	if got := publicMediaURL("http://example.test/imported-media/post.webp"); got != "http://example.test/imported-media/post.webp" {
		t.Fatalf("完整 URL 不应重复拼接公开前缀，得到 %q", got)
	}
	if got := publicMediaURL("ranking/beiyoujiang/cover.webp"); got != "http://example.test/imported-media/ranking/beiyoujiang/cover.webp" {
		t.Fatalf("相对对象键应拼接公开前缀，得到 %q", got)
	}
}
