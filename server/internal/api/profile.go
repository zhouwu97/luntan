package api

import (
	"database/sql"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

// profile 返回个人中心所需的聚合数据。列表接口保持统一的 cursor 形状，
// 让客户端可以复用 Feed/通知的分页状态机。
func (s *Server) profile(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var nickname, bio string
	var level int
	if err := s.db.QueryRowContext(r.Context(), `
		SELECT COALESCE(up.nickname, u.username), COALESCE(up.bio, ''), COALESCE(up.level, 1)
		FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id WHERE u.id = $1`, user.ID).
		Scan(&nickname, &bio, &level); err != nil {
		writeInternalError(w, r, err)
		return
	}
	var posts, comments, receivedLikes, followers, following int64
	queries := []struct {
		target *int64
		query  string
	}{
		{&posts, `SELECT count(*) FROM posts WHERE author_id = $1 AND publication_status = 'published' AND deleted_at IS NULL`},
		{&comments, `SELECT count(*) FROM comments WHERE author_id = $1 AND publication_status = 'published' AND deleted_at IS NULL`},
		{&receivedLikes, `SELECT count(*) FROM post_reactions pr JOIN posts p ON p.id = pr.post_id WHERE p.author_id = $1 AND p.deleted_at IS NULL`},
		{&followers, `SELECT count(*) FROM user_follows WHERE followee_id = $1`},
		{&following, `SELECT count(*) FROM user_follows WHERE follower_id = $1`},
	}
	for _, item := range queries {
		if err := s.db.QueryRowContext(r.Context(), item.query, user.ID).Scan(item.target); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"id": user.ID, "username": user.Username, "nickname": nickname,
		"level": level, "signature": bio, "post_count": posts,
		"comment_count": comments, "like_received_count": receivedLikes,
		"follower_count": followers, "following_count": following,
	})
}

func (s *Server) profileList(w http.ResponseWriter, r *http.Request, kind string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 无效"})
		return
	}
	// 个人中心第一版使用 created_at/id 作为稳定游标；history 使用 viewed_at。
	query, args, err := profileListQuery(kind, user.ID, r.URL.Query().Get("cursor"), limit)
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
		return
	}
	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	for rows.Next() {
		var id, title, content, communityID, communityName string
		var createdAt time.Time
		var commentCount, likeCount, bookmarkCount int64
		if err := rows.Scan(&id, &title, &content, &communityID, &communityName, &commentCount, &likeCount, &bookmarkCount, &createdAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, map[string]any{
			"id": id, "title": title, "content_preview": content,
			"community_id": communityID, "community_name": communityName,
			"comment_count": commentCount, "like_count": likeCount,
			"bookmark_count": bookmarkCount, "created_at": createdAt,
		})
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	var nextCursor any
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		nextCursor = encodeProfileCursor(last["created_at"].(time.Time), last["id"].(string))
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func profileListQuery(kind, userID, rawCursor string, limit int) (string, []any, error) {
	where := "p.deleted_at IS NULL AND p.publication_status = 'published'"
	args := []any{userID}
	join := "JOIN communities c ON c.id = p.community_id"
	timestampColumn := "p.created_at"
	switch kind {
	case "posts":
		where += " AND p.author_id = $1"
	case "comments":
		where += " AND EXISTS (SELECT 1 FROM comments c0 WHERE c0.post_id = p.id AND c0.author_id = $1 AND c0.deleted_at IS NULL)"
	case "likes":
		where += " AND EXISTS (SELECT 1 FROM post_reactions r0 WHERE r0.post_id = p.id AND r0.user_id = $1 AND r0.reaction_type = 'like')"
	case "bookmarks":
		where += " AND EXISTS (SELECT 1 FROM bookmarks b0 WHERE b0.post_id = p.id AND b0.user_id = $1)"
	case "history":
		join += " JOIN user_post_histories h ON h.post_id = p.id AND h.user_id = $1"
		timestampColumn = "h.viewed_at"
	default:
		return "", nil, fmt.Errorf("unknown profile list")
	}
	if rawCursor != "" {
		created, id, err := decodeProfileCursor(rawCursor)
		if err != nil {
			return "", nil, err
		}
		where += fmt.Sprintf(" AND (%s, p.id) < ($%d, $%d)", timestampColumn, len(args)+1, len(args)+2)
		args = append(args, created, id)
	}
	args = append(args, limit+1)
	limitPosition := len(args)
	return fmt.Sprintf(`
		SELECT p.id, p.title, LEFT(p.content, 200), p.community_id, c.name,
		       p.comment_count, p.like_count, p.bookmark_count, %s
		FROM posts p %s
		WHERE %s ORDER BY %s DESC, p.id DESC LIMIT $%d`, timestampColumn, join, where, timestampColumn, limitPosition), args, nil
}

func (s *Server) recordHistory(w http.ResponseWriter, r *http.Request, postID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var exists string
	if err := s.db.QueryRowContext(r.Context(), `SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL`, postID).Scan(&exists); err == sql.ErrNoRows {
		writeAuthError(w, r, ErrPostNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	result, err := s.db.ExecContext(r.Context(), `
		INSERT INTO user_post_histories (user_id, post_id, viewed_at) VALUES ($1, $2, now())
		ON CONFLICT (user_id, post_id) DO UPDATE SET viewed_at = EXCLUDED.viewed_at`, user.ID, postID)
	if err != nil {
		if err == sql.ErrNoRows {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "POST_NOT_FOUND", Message: "帖子不存在"})
			return
		}
		writeInternalError(w, r, err)
		return
	}
	_, _ = result.RowsAffected()
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"post_id": postID, "recorded": true})
}

func (s *Server) clearHistory(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if _, err := s.db.ExecContext(r.Context(), `DELETE FROM user_post_histories WHERE user_id = $1`, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"cleared": true})
}

func encodeProfileCursor(value time.Time, id string) string {
	return fmt.Sprintf("%d:%s", value.UnixNano(), id)
}

func decodeProfileCursor(value string) (time.Time, string, error) {
	parts := make([]string, 0, 2)
	// id 由服务端生成，不含冒号；保留 SplitN 语义以避免游标格式扩大攻击面。
	for index, part := range splitCursor(value) {
		if index < 2 {
			parts = append(parts, part)
		}
	}
	if len(parts) != 2 {
		return time.Time{}, "", fmt.Errorf("invalid cursor")
	}
	nanos, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil || parts[1] == "" {
		return time.Time{}, "", fmt.Errorf("invalid cursor")
	}
	return time.Unix(0, nanos).UTC(), parts[1], nil
}

func splitCursor(value string) []string {
	for index, char := range value {
		if char == ':' {
			return []string{value[:index], value[index+1:]}
		}
	}
	return nil
}
