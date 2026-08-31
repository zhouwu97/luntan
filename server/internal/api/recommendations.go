package api

import (
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type homeRecommendationItem struct {
	PostID        string        `json:"post_id"`
	Position      int           `json:"position"`
	RecommendedBy string        `json:"recommended_by"`
	RecommendedAt time.Time     `json:"recommended_at"`
	ExpiresAt     *time.Time    `json:"expires_at,omitempty"`
	Post          *postResponse `json:"post,omitempty"`
}

type setRecommendationInput struct {
	Position  *int       `json:"position"`
	ExpiresAt *time.Time `json:"expires_at"`
}

type reorderRecommendationItem struct {
	PostID   string `json:"post_id"`
	Position int    `json:"position"`
}

type reorderRecommendationsInput struct {
	Items []reorderRecommendationItem `json:"items"`
}

func (s *Server) listHomeRecommendations(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasGlobalPermission(r, user.ID, "moderation.action") {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}

	rows, err := s.db.QueryContext(r.Context(), `
		SELECT hr.post_id, hr.position, hr.recommended_by, hr.recommended_at, hr.expires_at,
		       p.id, p.author_id, u.username, COALESCE(up.nickname, u.username), p.community_id, c.slug, c.name,
		       p.type, p.title, p.content, p.comment_count, p.like_count, p.bookmark_count, p.share_count, p.view_count,
		       p.created_at, p.updated_at, p.published_at, p.publication_status, p.moderation_status
		FROM home_recommendations hr
		JOIN posts p ON p.id = hr.post_id
		JOIN users u ON u.id = p.author_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		JOIN communities c ON c.id = p.community_id
		WHERE p.deleted_at IS NULL
		ORDER BY hr.position ASC, hr.recommended_at DESC, p.id DESC`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()

	items := make([]homeRecommendationItem, 0)
	for rows.Next() {
		var item homeRecommendationItem
		var post postResponse
		err := rows.Scan(
			&item.PostID, &item.Position, &item.RecommendedBy, &item.RecommendedAt, &item.ExpiresAt,
			&post.ID, &post.Author.ID, &post.Author.Username, &post.Author.Nickname,
			&post.Community.ID, &post.Community.Slug, &post.Community.Name,
			&post.Type, &post.Title, &post.ContentPreview, &post.CommentCount, &post.LikeCount,
			&post.BookmarkCount, &post.ShareCount, &post.ViewCount, &post.CreatedAt,
			&post.UpdatedAt, &post.PublishedAt, &post.Publication, &post.Moderation,
		)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		post.ContentPreview = preview(post.ContentPreview)
		post.IsRecommended = true
		post.RecommendationPosition = &item.Position
		item.Post = &post
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) setHomeRecommendation(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasGlobalPermission(r, user.ID, "moderation.action") {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}

	var input setRecommendationInput
	if r.ContentLength > 0 {
		if err := decodeJSON(r, &input); err != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BODY", Message: "请求体格式错误"})
			return
		}
	}

	if input.ExpiresAt != nil && !input.ExpiresAt.After(time.Now().UTC()) {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusBadRequest,
			Code:    "INVALID_RECOMMENDATION_EXPIRY",
			Message: "推荐过期时间必须晚于当前时间",
		})
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()

	// Verify post exists, is not deleted, and matches feed public visibility rules
	var status, moderation, postType string
	var publishedAt sql.NullTime
	err = tx.QueryRowContext(r.Context(), `SELECT publication_status, moderation_status, type, published_at FROM posts WHERE id = $1 AND deleted_at IS NULL`, postID).Scan(&status, &moderation, &postType, &publishedAt)
	if errors.Is(err, sql.ErrNoRows) {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "POST_NOT_FOUND", Message: "帖子不存在或已删除"})
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if status != "published" || moderation != "normal" || postType == "market" || !publishedAt.Valid {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusBadRequest,
			Code:    "POST_NOT_RECOMMENDABLE",
			Message: "帖子未公开发布或处于审核/隐藏状态，不可加入首页推荐",
		})
		return
	}

	position := 0
	if input.Position != nil {
		position = *input.Position
	} else {
		var maxPos sql.NullInt64
		_ = tx.QueryRowContext(r.Context(), `SELECT MAX(position) FROM home_recommendations`).Scan(&maxPos)
		if maxPos.Valid {
			position = int(maxPos.Int64) + 1
		}
	}

	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO home_recommendations (post_id, recommended_by, position, recommended_at, expires_at)
		VALUES ($1, $2, $3, CURRENT_TIMESTAMP, $4)
		ON CONFLICT (post_id) DO UPDATE SET
			position = EXCLUDED.position,
			recommended_by = EXCLUDED.recommended_by,
			recommended_at = CURRENT_TIMESTAMP,
			expires_at = EXCLUDED.expires_at`,
		postID, user.ID, position, input.ExpiresAt)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	_ = appendAdminLogTx(r.Context(), tx, user.ID, "home_recommendation.set", "post", postID, "", requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{
		"position":   position,
		"expires_at": input.ExpiresAt,
	}, time.Now().UTC())

	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"success":  true,
		"post_id":  postID,
		"position": position,
	})
}

func (s *Server) removeHomeRecommendation(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasGlobalPermission(r, user.ID, "moderation.action") {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()

	res, err := tx.ExecContext(r.Context(), `DELETE FROM home_recommendations WHERE post_id = $1`, postID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	rowsAffected, _ := res.RowsAffected()

	_ = appendAdminLogTx(r.Context(), tx, user.ID, "home_recommendation.remove", "post", postID, "", requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{
		"removed": rowsAffected > 0,
	}, time.Now().UTC())

	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"success": true,
		"post_id": postID,
	})
}

func (s *Server) reorderHomeRecommendations(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasGlobalPermission(r, user.ID, "moderation.action") {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}

	var input reorderRecommendationsInput
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BODY", Message: "请求体格式错误"})
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()

	stmt, err := tx.PrepareContext(r.Context(), `UPDATE home_recommendations SET position = $1 WHERE post_id = $2`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer stmt.Close()

	for _, item := range input.Items {
		if _, err := stmt.ExecContext(r.Context(), item.Position, item.PostID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}

	_ = appendAdminLogTx(r.Context(), tx, user.ID, "home_recommendation.reorder", "system", "home_recommendations", "", requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{
		"count": len(input.Items),
	}, time.Now().UTC())

	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"success": true,
		"updated": len(input.Items),
	})
}

type setHotSuppressionInput struct {
	Suppressed bool   `json:"suppressed"`
	Reason     string `json:"reason,omitempty"`
}

func (s *Server) setPostHotSuppression(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasGlobalPermission(r, user.ID, "moderation.action") && !capabilitiesForUser(user)[capModerate] {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}

	var input setHotSuppressionInput
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BODY", Message: "请求体格式错误"})
		return
	}

	var exists bool
	if err := s.db.QueryRowContext(r.Context(), `SELECT EXISTS (SELECT 1 FROM posts WHERE id = $1 AND deleted_at IS NULL)`, postID).Scan(&exists); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if !exists {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "POST_NOT_FOUND", Message: "帖子不存在或已删除"})
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()

	now := time.Now().UTC()
	if input.Suppressed {
		_, err := tx.ExecContext(r.Context(), `
			UPDATE posts
			SET hot_suppressed = true,
			    hot_suppressed_by = $1,
			    hot_suppressed_at = $2,
			    hot_suppressed_reason = $3,
			    updated_at = now()
			WHERE id = $4`, user.ID, now, input.Reason, postID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	} else {
		_, err := tx.ExecContext(r.Context(), `
			UPDATE posts
			SET hot_suppressed = false,
			    hot_suppressed_by = NULL,
			    hot_suppressed_at = NULL,
			    hot_suppressed_reason = '',
			    updated_at = now()
			WHERE id = $1`, postID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	}

	if err := appendAdminLogTx(r.Context(), tx, user.ID, "post.hot_suppression", "post", postID, "", requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{
		"suppressed": input.Suppressed,
		"reason":     input.Reason,
	}, now); err != nil {
		writeInternalError(w, r, fmt.Errorf("failed to append admin log: %w", err))
		return
	}

	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"success":        true,
		"post_id":        postID,
		"hot_suppressed": input.Suppressed,
	})
}
