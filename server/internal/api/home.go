package api

import (
	"net/http"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type homeCommunity struct {
	ID            string `json:"id"`
	Slug          string `json:"slug"`
	Name          string `json:"name"`
	Description   string `json:"description"`
	MemberCount   int64  `json:"member_count"`
	FollowerCount int64  `json:"follower_count"`
	PostCount     int64  `json:"post_count"`
}

type homePost struct {
	ID            string    `json:"id"`
	Title         string    `json:"title"`
	Content       string    `json:"content_preview"`
	CommunityID   string    `json:"community_id"`
	CommunityName string    `json:"community_name"`
	LikeCount     int64     `json:"like_count"`
	CommentCount  int64     `json:"comment_count"`
	CreatedAt     time.Time `json:"created_at"`
}

func (s *Server) home(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	communities, err := s.homeCommunities(r)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	featured, err := s.homeFeaturedPosts(r)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"communities": communities,
		"shortcuts": []map[string]string{
			{"key": "latest", "title": "最新"},
			{"key": "featured", "title": "精华"},
			{"key": "question", "title": "问答"},
			{"key": "market", "title": "市场"},
		},
		"featured": featured,
	})
}

func (s *Server) homeCommunities(r *http.Request) ([]homeCommunity, error) {
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT id, slug, name, description, member_count, follower_count, post_count
		FROM communities
		WHERE status = 'active' AND deleted_at IS NULL
		ORDER BY sort_order ASC, post_count DESC, id ASC
		LIMIT 8`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]homeCommunity, 0, 8)
	for rows.Next() {
		var item homeCommunity
		if err := rows.Scan(&item.ID, &item.Slug, &item.Name, &item.Description, &item.MemberCount, &item.FollowerCount, &item.PostCount); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Server) homeFeaturedPosts(r *http.Request) ([]homePost, error) {
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT p.id, p.title, LEFT(p.content, 200), p.community_id, c.name,
		       p.like_count, p.comment_count, p.published_at
		FROM posts p
		JOIN communities c ON c.id = p.community_id
		WHERE p.publication_status = 'published' AND p.moderation_status = 'normal'
		  AND p.deleted_at IS NULL AND p.published_at IS NOT NULL
		  AND c.status = 'active' AND c.deleted_at IS NULL
		ORDER BY (p.like_count + p.comment_count * 2) DESC, p.published_at DESC, p.id DESC
		LIMIT 6`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]homePost, 0, 6)
	for rows.Next() {
		var item homePost
		if err := rows.Scan(&item.ID, &item.Title, &item.Content, &item.CommunityID, &item.CommunityName, &item.LikeCount, &item.CommentCount, &item.CreatedAt); err != nil {
			return nil, err
		}
		item.Content = preview(item.Content)
		items = append(items, item)
	}
	return items, rows.Err()
}
