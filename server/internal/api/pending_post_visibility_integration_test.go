package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"
)

// 回归：待审核（pending）帖子曾对作者本人也返回 404，导致用户看到「发布成功」
// 后，在详情页、个人主页和搜索里都找不到自己的帖子，等价于内容丢失。
func TestPendingPostVisibleToAuthor(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)

	suffix := time.Now().UnixNano()
	email := fmt.Sprintf("itest-pend-%d@example.com", suffix)
	username := fmt.Sprintf("itest_pend_%d", suffix%100000000)
	token := registerAndLogin(t, handler, email, username, "password123")

	var authorID string
	if err := s.db.QueryRow(`SELECT id FROM users WHERE lower(email) = $1`, email).Scan(&authorID); err != nil {
		t.Fatal(err)
	}

	postID := fmt.Sprintf("itest-pending-post-%d", suffix)
	if _, err := s.db.Exec(`
		INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, created_at, updated_at, published_at)
		VALUES ($1, $2, 'community-unboxing', 'normal', 'published', 'pending', $3, 'pending body', now(), now(), now())`,
		postID, authorID, fmt.Sprintf("pending-%d", suffix)); err != nil {
		t.Fatal(err)
	}

	t.Run("作者本人可见", func(t *testing.T) {
		code, body := callBusinessAPI(handler, http.MethodGet, "/api/v1/posts/"+postID, token, nil, nil)
		if code != http.StatusOK {
			t.Fatalf("作者应能查看自己的待审核帖子，实际 %d：%s", code, body)
		}
		var resp map[string]any
		_ = json.Unmarshal(body, &resp)
		if resp["moderation_status"] != "pending" {
			t.Fatalf("作者视图应如实返回 pending 状态，实际 %v", resp["moderation_status"])
		}
	})

	t.Run("其他访客不可见", func(t *testing.T) {
		code, _ := callBusinessAPI(handler, http.MethodGet, "/api/v1/posts/"+postID, "", nil, nil)
		if code != http.StatusNotFound {
			t.Fatalf("待审核帖子对公众应返回 404，实际 %d", code)
		}
	})

	t.Run("作者个人主页包含待审核内容", func(t *testing.T) {
		code, body := callBusinessAPI(handler, http.MethodGet, "/api/v1/users/"+authorID+"/posts?limit=20", token, nil, nil)
		if code != http.StatusOK {
			t.Fatalf("读取本人发布列表失败：%d %s", code, body)
		}
		var resp struct {
			Items []struct {
				ID string `json:"id"`
			} `json:"items"`
		}
		_ = json.Unmarshal(body, &resp)
		found := false
		for _, item := range resp.Items {
			if item.ID == postID {
				found = true
			}
		}
		if !found {
			t.Fatalf("本人发布列表应包含待审核帖子 %s，实际返回 %d 条", postID, len(resp.Items))
		}
	})

	t.Run("他人查看该用户主页不包含待审核内容", func(t *testing.T) {
		code, body := callBusinessAPI(handler, http.MethodGet, "/api/v1/users/"+authorID+"/posts?limit=20", "", nil, nil)
		if code != http.StatusOK {
			t.Fatalf("读取他人发布列表失败：%d %s", code, body)
		}
		var resp struct {
			Items []struct {
				ID string `json:"id"`
			} `json:"items"`
		}
		_ = json.Unmarshal(body, &resp)
		for _, item := range resp.Items {
			if item.ID == postID {
				t.Fatalf("待审核帖子不应出现在公开的个人主页中")
			}
		}
	})
}
