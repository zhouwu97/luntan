package api

import (
	"database/sql"
	"fmt"
	"net/http"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type userProfileResponse struct {
	ID                string         `json:"id"`
	PublicID          string         `json:"public_id"`
	Username          string         `json:"username"`
	Nickname          string         `json:"nickname"`
	AvatarMediaID     string         `json:"avatar_media_id,omitempty"`
	AvatarURL         string         `json:"avatar_url,omitempty"`
	BackgroundMediaID string         `json:"background_media_id,omitempty"`
	BackgroundURL     string         `json:"background_url,omitempty"`
	Bio               string         `json:"bio"`
	Level             int            `json:"level"`
	Experience        int64          `json:"experience"`
	AccountType       string         `json:"account_type"`
	Growth            GrowthState    `json:"growth"`
	TrustLevel        string         `json:"trust_level"`
	Status            string         `json:"status"`
	PostCount         int64          `json:"post_count"`
	CommentCount      int64          `json:"comment_count"`
	FollowerCount     int64          `json:"follower_count"`
	FollowingCount    int64          `json:"following_count"`
	CreatedAt         string         `json:"created_at"`
	ViewerState       map[string]any `json:"viewer_state"`
}

func (s *Server) getUserProfile(w http.ResponseWriter, r *http.Request, id string) {
	if !s.requireDatabase(w, r) {
		return
	}
	var item userProfileResponse
	var createdAt sql.NullTime
	var backgroundObjectKey string
	var avatarObjectKey string
	var viewerID, accountType string
	var exp int64
	var rawLevel int
	viewer, hasViewer := s.optionalAuthenticatedUser(r.Context(), r)
	if hasViewer {
		viewerID = viewer.ID
	}
	err := s.db.QueryRowContext(r.Context(), `
		SELECT u.id, COALESCE(u.public_id::text, ''), u.username, COALESCE(up.nickname, u.username),
		       COALESCE(up.avatar_media_id, ''), COALESCE(avatar.object_key, ''),
		       COALESCE(up.background_media_id, ''), COALESCE(background.object_key, ''), COALESCE(up.bio, ''),
		       CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
		       COALESCE(up.trust_level, 'new'), u.status, u.created_at,
		       COALESCE(up.experience, 0), COALESCE(u.account_type, 'email'),
		       (SELECT count(*) FROM posts p WHERE p.author_id = u.id AND p.deleted_at IS NULL AND p.publication_status = 'published' AND p.type <> 'market' AND (p.moderation_status = 'normal' OR (p.author_id = $2 AND p.moderation_status = 'pending'))),
		       (SELECT count(*) FROM comments c JOIN posts p ON p.id = c.post_id WHERE c.author_id = u.id AND c.deleted_at IS NULL AND c.publication_status = 'published' AND c.moderation_status = 'normal' AND p.deleted_at IS NULL AND p.publication_status = 'published' AND p.moderation_status = 'normal' AND p.type <> 'market'),
		       (SELECT count(*) FROM user_follows f WHERE f.followee_id = u.id),
		       (SELECT count(*) FROM user_follows f WHERE f.follower_id = u.id)
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets avatar ON avatar.id = up.avatar_media_id AND avatar.status = 'ready' AND avatar.deleted_at IS NULL
		LEFT JOIN media_assets background ON background.id = up.background_media_id AND background.status = 'ready' AND background.deleted_at IS NULL
		WHERE u.id = $1 AND u.deleted_at IS NULL`, id, viewerID).
		Scan(&item.ID, &item.PublicID, &item.Username, &item.Nickname, &item.AvatarMediaID, &avatarObjectKey, &item.BackgroundMediaID, &backgroundObjectKey, &item.Bio,
			&rawLevel, &item.TrustLevel, &item.Status, &createdAt, &exp, &accountType, &item.PostCount, &item.CommentCount, &item.FollowerCount, &item.FollowingCount)
	if err == sql.ErrNoRows {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusNotFound, Code: "NOT_FOUND", Message: "用户不存在"})
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	item.AccountType = accountType
	growth := growthState(accountType, exp)
	item.Level = growth.Level
	item.Experience = growth.Experience
	item.Growth = growth
	if createdAt.Valid {
		item.CreatedAt = createdAt.Time.UTC().Format("2006-01-02T15:04:05.999999Z07:00")
	}
	if avatarObjectKey != "" {
		item.AvatarURL = mediaVariantURL(item.AvatarMediaID, avatarObjectKey, "thumb")
	}
	if backgroundObjectKey != "" {
		item.BackgroundURL = mediaVariantURL(item.BackgroundMediaID, backgroundObjectKey, "detail")
	}
	item.ViewerState = map[string]any{
		"is_following": false,
		"is_blocked":   false,
		"can_follow":   hasViewer && capabilitiesForUser(viewer)[capFollow] && viewerID != item.ID,
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
		item.ViewerState["can_follow"] = capabilitiesForUser(viewer)[capFollow] && viewerID != item.ID && !isBlocked
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
	// 本人查看自己的发布时包含待审核内容，否则刚发布的帖子会在自己的列表里消失。
	viewer, viewerOK := resolveOptionalViewer(s, r)
	includePending := viewerOK && viewer.ID != "" && viewer.ID == userID
	query, args, err := profileListQueryFor("posts", userID, r.URL.Query().Get("cursor"), limit, includePending)
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
		var id, title, content, communityID, communityName, publicationStatus, moderationStatus string
		var createdAt time.Time
		var commentCount, likeCount, bookmarkCount, viewCount int64
		if err := rows.Scan(&id, &title, &content, &communityID, &communityName, &commentCount, &likeCount, &bookmarkCount, &viewCount, &createdAt, &publicationStatus, &moderationStatus); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, map[string]any{
			"id": id, "title": title, "content_preview": content,
			"community_id": communityID, "community_name": communityName,
			"comment_count": commentCount, "like_count": likeCount,
			"bookmark_count": bookmarkCount, "created_at": createdAt,
			"view_count":         viewCount,
			"published_at":       createdAt,
			"publication_status": publicationStatus,
			"moderation_status":  moderationStatus,
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

// listUserRelations 提供关注者/关注列表的稳定游标分页，避免客户端只展示聚合数字。
func (s *Server) listUserRelations(w http.ResponseWriter, r *http.Request, userID, relation string) {
	if !s.requireDatabase(w, r) {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 无效"})
		return
	}
	if relation != "followers" && relation != "following" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_RELATION", Message: "关系类型无效"})
		return
	}

	viewer, hasViewer := s.optionalAuthenticatedUser(r.Context(), r)
	viewerID := ""
	if hasViewer {
		viewerID = viewer.ID
	}

	joinColumn := "f.followee_id"
	whereColumn := "f.follower_id"
	if relation == "followers" {
		joinColumn = "f.follower_id"
		whereColumn = "f.followee_id"
	}
	// 固定保留 viewer 参数，让列表查询一次性带回关系状态，避免每个用户再查一次。
	args := []any{userID, viewerID}
	where := fmt.Sprintf("f.%s = $1", whereColumn[2:])
	if rawCursor := r.URL.Query().Get("cursor"); rawCursor != "" {
		created, id, err := decodeProfileCursor(rawCursor)
		if err != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		where += " AND (f.created_at, u.id) < ($3, $4)"
		args = append(args, created, id)
	}
	args = append(args, limit+1)
	limitPosition := len(args)
	query := fmt.Sprintf(`
		SELECT u.id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(up.avatar_media_id, ''), f.created_at,
		       EXISTS (SELECT 1 FROM user_follows vf WHERE vf.follower_id = $2 AND vf.followee_id = u.id),
		       EXISTS (SELECT 1 FROM blocks vb WHERE (vb.blocker_id = $2 AND vb.blocked_id = u.id) OR (vb.blocker_id = u.id AND vb.blocked_id = $2)),
		       ($2 <> '' AND $2 <> u.id AND NOT EXISTS (SELECT 1 FROM blocks vb WHERE (vb.blocker_id = $2 AND vb.blocked_id = u.id) OR (vb.blocker_id = u.id AND vb.blocked_id = $2)))
		FROM user_follows f
		JOIN users u ON u.id = %s
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE %s AND u.deleted_at IS NULL
		ORDER BY f.created_at DESC, u.id DESC LIMIT $%d`, joinColumn, where, limitPosition)
	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()

	items := make([]map[string]any, 0, limit+1)
	for rows.Next() {
		var id, username, nickname, avatarMediaID string
		var createdAt time.Time
		var isFollowing, isBlocked, canFollow bool
		if err := rows.Scan(&id, &username, &nickname, &avatarMediaID, &createdAt, &isFollowing, &isBlocked, &canFollow); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if hasViewer && !capabilitiesForUser(viewer)[capFollow] {
			canFollow = false
		}
		items = append(items, map[string]any{
			"id": id, "username": username, "nickname": nickname,
			"avatar_media_id": avatarMediaID, "created_at": createdAt,
			"viewer_state": map[string]any{
				"is_following": isFollowing, "is_blocked": isBlocked, "can_follow": canFollow,
			},
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
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"items": items, "next_cursor": nextCursor, "has_more": hasMore,
		"user_id": userID, "relation": relation,
	})
}

// listUserComments 提供主页「评论」Tab 的数据；展示公开的未删除评论。
func (s *Server) listUserComments(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 无效"})
		return
	}
	// 公开接口不返回评论正文，只返回评论过的帖子信息
	s.profileCommentList(w, r, userID, limit, false)
}
