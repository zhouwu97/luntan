package api

import (
	"database/sql"
	"net/http"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type userProfileResponse struct {
	ID             string         `json:"id"`
	Username       string         `json:"username"`
	Nickname       string         `json:"nickname"`
	AvatarMediaID  string         `json:"avatar_media_id,omitempty"`
	Bio            string         `json:"bio"`
	Level          int            `json:"level"`
	TrustLevel     string         `json:"trust_level"`
	Status         string         `json:"status"`
	PostCount      int64          `json:"post_count"`
	FollowerCount  int64          `json:"follower_count"`
	FollowingCount int64          `json:"following_count"`
	CreatedAt      string         `json:"created_at"`
	ViewerState    map[string]any `json:"viewer_state"`
}

func (s *Server) getUserProfile(w http.ResponseWriter, r *http.Request, id string) {
	if !s.requireDatabase(w, r) {
		return
	}
	var item userProfileResponse
	var createdAt sql.NullTime
	var viewerID string
	viewer, hasViewer := s.optionalAuthenticatedUser(r.Context(), r)
	if hasViewer {
		viewerID = viewer.ID
	}
	err := s.db.QueryRowContext(r.Context(), `
		SELECT u.id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(up.avatar_media_id, ''), COALESCE(up.bio, ''),
		       COALESCE(up.level, 1), COALESCE(up.trust_level, 'new'), u.status, u.created_at,
		       (SELECT count(*) FROM posts p WHERE p.author_id = u.id AND p.deleted_at IS NULL AND p.publication_status = 'published'),
		       (SELECT count(*) FROM user_follows f WHERE f.followee_id = u.id),
		       (SELECT count(*) FROM user_follows f WHERE f.follower_id = u.id)
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE u.id = $1 AND u.deleted_at IS NULL`, id).
		Scan(&item.ID, &item.Username, &item.Nickname, &item.AvatarMediaID, &item.Bio,
			&item.Level, &item.TrustLevel, &item.Status, &createdAt, &item.PostCount, &item.FollowerCount, &item.FollowingCount)
	if err == sql.ErrNoRows {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "用户不存在"})
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if createdAt.Valid {
		item.CreatedAt = createdAt.Time.UTC().Format("2006-01-02T15:04:05.999999Z07:00")
	}
	item.ViewerState = map[string]any{
		"is_following": false,
		"is_blocked":   false,
		"can_follow":   viewerID != "" && viewerID != item.ID,
	}
	if viewerID != "" {
		var isFollowing, isBlocked bool
		if err := s.db.QueryRowContext(r.Context(), `
			SELECT EXISTS (SELECT 1 FROM user_follows WHERE follower_id = $1 AND followee_id = $2),
			       EXISTS (SELECT 1 FROM blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1))`, viewerID, item.ID).
			Scan(&isFollowing, &isBlocked); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item.ViewerState["is_following"] = isFollowing
		item.ViewerState["is_blocked"] = isBlocked
		item.ViewerState["can_follow"] = viewerID != item.ID && !isBlocked
	}
	httpserver.WriteJSON(w, http.StatusOK, item)
}

func (s *Server) listUserPosts(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 无效"})
		return
	}
	query, args, err := profileListQuery("posts", userID, r.URL.Query().Get("cursor"), limit)
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
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore, "user_id": userID})
}
