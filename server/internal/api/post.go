package api

import (
	"database/sql"
	"net/http"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

func (s *Server) getPost(w http.ResponseWriter, r *http.Request, id string) {
	if !s.requireDatabase(w, r) {
		return
	}
	var row postResponse
	var deletedAt sql.NullTime
	var publishedAt sql.NullTime
	err := s.db.QueryRowContext(r.Context(), `
		SELECT p.id, p.author_id, u.username, COALESCE(up.nickname, u.username), p.community_id, c.slug, c.name,
		       p.type, p.title, p.content, p.comment_count, p.like_count, p.bookmark_count, p.share_count, p.view_count,
		p.created_at, p.updated_at, p.published_at, p.publication_status, p.moderation_status, p.deleted_at
		FROM posts p
		JOIN users u ON u.id = p.author_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		JOIN communities c ON c.id = p.community_id
		WHERE p.id = $1`, id).Scan(&row.ID, &row.Author.ID, &row.Author.Username, &row.Author.Nickname, &row.Community.ID, &row.Community.Slug, &row.Community.Name, &row.Type, &row.Title, &row.Content, &row.CommentCount, &row.LikeCount, &row.BookmarkCount, &row.ShareCount, &row.ViewCount, &row.CreatedAt, &row.UpdatedAt, &publishedAt, &row.Publication, &row.Moderation, &deletedAt)
	if err == sql.ErrNoRows {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "帖子不存在"})
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if deletedAt.Valid || row.Publication != "published" || row.Moderation != "normal" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "帖子不存在"})
		return
	}
	if publishedAt.Valid {
		row.PublishedAt = &publishedAt.Time
	}
	httpserver.WriteJSON(w, http.StatusOK, row)
}
