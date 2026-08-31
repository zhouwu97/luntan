package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type profileUpdateInput struct {
	Nickname          *string `json:"nickname"`
	Bio               *string `json:"bio"`
	AvatarMediaID     *string `json:"avatar_media_id"`
	BackgroundMediaID *string `json:"background_media_id"`
}

func (s *Server) updateProfile(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.requireCapability(w, r, user, capManageProfile) {
		return
	}
	var input profileUpdateInput
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, auth.ErrInvalidInput)
		return
	}
	nickname := strings.TrimSpace(user.Nickname)
	bio := ""
	if input.Nickname == nil || input.Bio == nil {
		var currentNickname, currentBio string
		if err := s.db.QueryRowContext(r.Context(), `
			SELECT COALESCE(up.nickname, u.username), COALESCE(up.bio, '')
			FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id
			WHERE u.id = $1`, user.ID).Scan(&currentNickname, &currentBio); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if input.Nickname == nil {
			nickname = strings.TrimSpace(currentNickname)
		}
		if input.Bio == nil {
			bio = strings.TrimSpace(currentBio)
		}
	}
	if input.Nickname != nil {
		nickname = strings.TrimSpace(*input.Nickname)
	}
	if input.Bio != nil {
		bio = strings.TrimSpace(*input.Bio)
	}
	if nickname == "" || len([]rune(nickname)) > 64 || len([]rune(bio)) > 200 {
		writeAuthError(w, r, auth.ErrInvalidInput)
		return
	}
	avatarMediaID := ""
	if input.AvatarMediaID != nil {
		avatarMediaID = strings.TrimSpace(*input.AvatarMediaID)
		if avatarMediaID != "" {
			var ownedID string
			if err := s.db.QueryRowContext(r.Context(), `SELECT id FROM media_assets WHERE id = $1 AND owner_id = $2 AND status = 'ready' AND deleted_at IS NULL`, avatarMediaID, user.ID).Scan(&ownedID); err != nil {
				if errors.Is(err, sql.ErrNoRows) {
					writeAuthError(w, r, ErrMediaNotFound)
					return
				}
				writeInternalError(w, r, err)
				return
			}
		}
	} else {
		// PATCH 未携带头像字段时保留现有头像；只有显式传空字符串才代表移除头像。
		if err := s.db.QueryRowContext(r.Context(), `SELECT COALESCE(avatar_media_id, '') FROM user_profiles WHERE user_id = $1`, user.ID).Scan(&avatarMediaID); err != nil && !errors.Is(err, sql.ErrNoRows) {
			writeInternalError(w, r, err)
			return
		}
	}
	backgroundMediaID := ""
	if input.BackgroundMediaID != nil {
		backgroundMediaID = strings.TrimSpace(*input.BackgroundMediaID)
		if backgroundMediaID != "" {
			var ownedID string
			if err := s.db.QueryRowContext(r.Context(), `SELECT id FROM media_assets WHERE id = $1 AND owner_id = $2 AND status = 'ready' AND deleted_at IS NULL`, backgroundMediaID, user.ID).Scan(&ownedID); err != nil {
				if errors.Is(err, sql.ErrNoRows) {
					writeAuthError(w, r, ErrMediaNotFound)
					return
				}
				writeInternalError(w, r, err)
				return
			}
		}
	} else {
		// PATCH 未携带背景字段时保留原背景；传空字符串可移除用户自定义背景。
		if err := s.db.QueryRowContext(r.Context(), `SELECT COALESCE(background_media_id, '') FROM user_profiles WHERE user_id = $1`, user.ID).Scan(&backgroundMediaID); err != nil && !errors.Is(err, sql.ErrNoRows) {
			writeInternalError(w, r, err)
			return
		}
	}
	if _, err := s.db.ExecContext(r.Context(), `UPDATE user_profiles SET nickname = $1, bio = $2, avatar_media_id = NULLIF($3, ''), background_media_id = NULLIF($4, ''), updated_at = now() WHERE user_id = $5`, nickname, bio, avatarMediaID, backgroundMediaID, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	var avatar, background any
	if avatarMediaID != "" {
		avatar = avatarMediaID
	}
	if backgroundMediaID != "" {
		background = backgroundMediaID
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"id": user.ID, "username": user.Username, "nickname": nickname,
		"signature": bio, "avatar_media_id": avatar, "background_media_id": background,
	})
}

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
	var publicID, nickname, bio, trustLevel, avatarObjectKey, backgroundObjectKey, accountType string
	var avatarMediaID, backgroundMediaID sql.NullString
	var level int
	var exp int64
	if err := s.db.QueryRowContext(r.Context(), `
        SELECT COALESCE(u.public_id::text, ''), COALESCE(up.nickname, u.username), COALESCE(up.bio, ''), COALESCE(up.avatar_media_id, ''),
               COALESCE(ma.object_key, ''), COALESCE(up.background_media_id, ''), COALESCE(background.object_key, ''),
               CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
		       COALESCE(up.trust_level, 'new'), COALESCE(up.experience, 0), COALESCE(u.account_type, 'email')
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
        LEFT JOIN media_assets ma ON ma.id = up.avatar_media_id AND ma.status = 'ready' AND ma.deleted_at IS NULL
        LEFT JOIN media_assets background ON background.id = up.background_media_id AND background.status = 'ready' AND background.deleted_at IS NULL
        WHERE u.id = $1`, user.ID).
		Scan(&publicID, &nickname, &bio, &avatarMediaID, &avatarObjectKey, &backgroundMediaID, &backgroundObjectKey, &level, &trustLevel, &exp, &accountType); err != nil {
		writeInternalError(w, r, err)
		return
	}
	growth := growthState(accountType, exp)
	var posts, comments, receivedLikes, followers, following int64
	queries := []struct {
		target *int64
		query  string
	}{
		{&posts, `SELECT count(*) FROM posts WHERE author_id = $1 AND publication_status = 'published' AND type <> 'market' AND deleted_at IS NULL`},
		{&comments, `SELECT count(*) FROM comments WHERE author_id = $1 AND publication_status = 'published' AND deleted_at IS NULL`},
		{&receivedLikes, `SELECT count(*) FROM post_reactions pr JOIN posts p ON p.id = pr.post_id WHERE p.author_id = $1 AND p.type <> 'market' AND p.deleted_at IS NULL`},
		{&followers, `SELECT count(*) FROM user_follows WHERE followee_id = $1`},
		{&following, `SELECT count(*) FROM user_follows WHERE follower_id = $1`},
	}
	for _, item := range queries {
		if err := s.db.QueryRowContext(r.Context(), item.query, user.ID).Scan(item.target); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	response := map[string]any{
		"id": user.ID, "username": user.Username, "nickname": nickname,
		"public_id":           publicID,
		"account_type":        accountType,
		"avatar_media_id":     nullableProfileString(avatarMediaID),
		"background_media_id": nullableProfileString(backgroundMediaID),
		"level":               growth.Level, "experience": growth.Experience, "growth": growth,
		"trust_level": trustLevel, "signature": bio, "post_count": posts,
		"comment_count": comments, "like_received_count": receivedLikes,
		"follower_count": followers, "following_count": following,
	}
	if avatarObjectKey != "" {
		response["avatar_url"] = publicMediaURL(avatarObjectKey)
	}
	if backgroundObjectKey != "" {
		response["background_url"] = publicMediaURL(backgroundObjectKey)
	}
	httpserver.WriteJSON(w, http.StatusOK, response)
}

func nullableProfileString(value sql.NullString) any {
	if !value.Valid || strings.TrimSpace(value.String) == "" {
		return nil
	}
	return value.String
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
	if includePostDetails(r) {
		s.profileDetailedList(w, r, user.ID, kind, limit)
		return
	}
	if kind == "comments" {
		s.profileCommentList(w, r, user.ID, limit)
		return
	}
	// 帖子类个人列表按发布时间；history 使用 viewed_at。
	includePending := kind == "posts"
	query, args, err := profileListQueryFor(kind, user.ID, r.URL.Query().Get("cursor"), limit, includePending)
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
			"view_count":   viewCount,
			"published_at": createdAt,
			"publication_status": publicationStatus,
			"moderation_status": moderationStatus,
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

// profileCommentList 返回当前认证用户发表的评论列表，一条评论对应一条列表项。
func (s *Server) profileCommentList(w http.ResponseWriter, r *http.Request, userID string, limit int) {
	query, args, err := profileCommentListQuery(userID, r.URL.Query().Get("cursor"), limit)
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
		var commentID, postID, title, content, communityID, communityName string
		var publishedAt, activityAt time.Time
		var commentCount, likeCount, bookmarkCount int64
		if err := rows.Scan(&commentID, &postID, &title, &content, &communityID, &communityName, &commentCount, &likeCount, &bookmarkCount, &publishedAt, &activityAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, map[string]any{
			"id": postID, "comment_id": commentID, "title": title, "content_preview": content,
			"community_id": communityID, "community_name": communityName,
			"comment_count": commentCount, "like_count": likeCount,
			"bookmark_count": bookmarkCount, "published_at": publishedAt,
			"activity_at": activityAt,
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
		nextCursor = encodeProfileCursor(last["activity_at"].(time.Time), last["comment_id"].(string))
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func profileCommentListQuery(userID, rawCursor string, limit int) (string, []any, error) {
	args := []any{userID}
	where := `c.author_id = $1 AND c.publication_status = 'published' AND c.moderation_status = 'normal' AND c.deleted_at IS NULL
		AND p.publication_status = 'published' AND p.moderation_status = 'normal' AND p.deleted_at IS NULL AND p.type <> 'market'`
	if rawCursor != "" {
		createdAt, id, err := decodeProfileCursor(rawCursor)
		if err != nil {
			return "", nil, err
		}
		where += " AND (c.created_at, c.id) < ($2, $3)"
		args = append(args, createdAt, id)
	}
	args = append(args, limit+1)
	return fmt.Sprintf(`
		SELECT c.id, p.id, p.title, LEFT(c.content, 200), p.community_id, cm.name,
		       p.comment_count, p.like_count, p.bookmark_count,
		       COALESCE(p.published_at, p.created_at), c.created_at
		FROM comments c
		JOIN posts p ON p.id = c.post_id
		JOIN communities cm ON cm.id = p.community_id
		WHERE %s
		ORDER BY c.created_at DESC, c.id DESC
		LIMIT $%d`, where, len(args)), args, nil
}

func profileListQuery(kind, userID, rawCursor string, limit int) (string, []any, error) {
	return profileListQueryFor(kind, userID, rawCursor, limit, false)
}

// profileListQueryFor 构建个人中心列表查询。includePending 为真时把待审核内容一并
// 返回，仅用于「本人查看自己的发布」，避免用户发布后内容在自己的列表里凭空消失。
func profileListQueryFor(kind, userID, rawCursor string, limit int, includePending bool) (string, []any, error) {
	moderationFilter := "p.moderation_status = 'normal'"
	if includePending {
		moderationFilter = "p.moderation_status IN ('normal', 'pending')"
	}
	where := "p.deleted_at IS NULL AND p.publication_status = 'published' AND " + moderationFilter + " AND p.type <> 'market'"
	args := []any{userID}
	join := "JOIN communities c ON c.id = p.community_id"
	timestampColumn := "COALESCE(p.published_at, p.created_at)"
	switch kind {
	case "posts":
		where += " AND p.author_id = $1"
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
		       p.comment_count, p.like_count, p.bookmark_count, p.view_count, %s,
		       p.publication_status, p.moderation_status
		FROM posts p %s
		WHERE %s ORDER BY %s DESC, p.id DESC LIMIT $%d`, timestampColumn, join, where, timestampColumn, limitPosition), args, nil
}

// profileDetailedList 是首页个人 Feed 使用的完整帖子摘要接口。个人中心旧列表
// 继续走上面的轻量查询；首页显式传 include_details=1 时，直接返回和公共 Feed
// 一致的帖子卡片数据，避免客户端再为每一项请求一次帖子详情。
func (s *Server) profileDetailedList(w http.ResponseWriter, r *http.Request, userID, kind string, limit int) {
	if kind == "comments" {
		s.profileDetailedCommentList(w, r, userID, limit)
		return
	}
	includePending := kind == "posts"
	query, args, err := profileDetailedListQuery(kind, userID, r.URL.Query().Get("cursor"), limit, includePending)
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
	sortTimes := make([]time.Time, 0, limit+1)
	for rows.Next() {
		var row postResponse
		var publishedAt sql.NullTime
		var sortAt time.Time
		if err := rows.Scan(
			&row.ID, &row.Author.ID, &row.Author.Username, &row.Author.Nickname, &row.Author.Level,
			&row.Community.ID, &row.Community.Slug, &row.Community.Name,
			&row.Type, &row.Title, &row.Content, &row.CommentCount, &row.LikeCount,
			&row.BookmarkCount, &row.ShareCount, &row.ViewCount, &row.CreatedAt,
			&row.UpdatedAt, &publishedAt, &sortAt,
			&row.Publication, &row.Moderation,
		); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if publishedAt.Valid {
			row.PublishedAt = &publishedAt.Time
		}
		if err := s.enrichPostResponse(r.Context(), r, &row, true); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, profilePostItemMap(row, nil))
		sortTimes = append(sortTimes, sortAt)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
		sortTimes = sortTimes[:limit]
	}
	var nextCursor any
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		nextCursor = encodeProfileCursor(sortTimes[len(sortTimes)-1], last["id"].(string))
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func (s *Server) profileDetailedCommentList(w http.ResponseWriter, r *http.Request, userID string, limit int) {
	query, args, err := profileDetailedCommentListQuery(userID, r.URL.Query().Get("cursor"), limit)
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
	activityTimes := make([]time.Time, 0, limit+1)
	for rows.Next() {
		var row postResponse
		var publishedAt, activityAt time.Time
		if err := rows.Scan(
			&row.ID, &row.Author.ID, &row.Author.Username, &row.Author.Nickname, &row.Author.Level,
			&row.Community.ID, &row.Community.Slug, &row.Community.Name,
			&row.Type, &row.Title, &row.Content, &row.CommentCount, &row.LikeCount,
			&row.BookmarkCount, &row.ShareCount, &row.ViewCount, &row.CreatedAt,
			&row.UpdatedAt, &publishedAt, &activityAt,
		); err != nil {
			writeInternalError(w, r, err)
			return
		}
		row.Publication = "published"
		row.Moderation = "normal"
		row.PublishedAt = &publishedAt
		if err := s.enrichPostResponse(r.Context(), r, &row, true); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, profilePostItemMap(row, &activityAt))
		activityTimes = append(activityTimes, activityAt)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
		activityTimes = activityTimes[:limit]
	}
	var nextCursor any
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		nextCursor = encodeProfileCursor(activityTimes[len(activityTimes)-1], last["id"].(string))
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func profileDetailedListQuery(kind, userID, rawCursor string, limit int, includePending bool) (string, []any, error) {
	moderationFilter := "p.moderation_status = 'normal'"
	if includePending {
		moderationFilter = "p.moderation_status IN ('normal', 'pending')"
	}
	where := "p.deleted_at IS NULL AND p.publication_status = 'published' AND " + moderationFilter + " AND p.type <> 'market'"
	args := []any{userID}
	join := "JOIN communities c ON c.id = p.community_id"
	timestampColumn := "COALESCE(p.published_at, p.created_at)"
	switch kind {
	case "posts":
		where += " AND p.author_id = $1"
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
		SELECT p.id, p.author_id, u.username, COALESCE(up.nickname, u.username), COALESCE(up.level, 1),
		       p.community_id, c.slug, c.name, p.type, p.title, p.content,
		       p.comment_count, p.like_count, p.bookmark_count, p.share_count, p.view_count,
		       p.created_at, p.updated_at, p.published_at, %s AS sort_at,
		       p.publication_status, p.moderation_status
		FROM posts p
		JOIN users u ON u.id = p.author_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		%s
		WHERE %s ORDER BY %s DESC, p.id DESC LIMIT $%d`, timestampColumn, join, where, timestampColumn, limitPosition), args, nil
}

func profileDetailedCommentListQuery(userID, rawCursor string, limit int) (string, []any, error) {
	args := []any{userID}
	where := `p.author_id = $1 AND p.publication_status = 'published' AND p.moderation_status = 'normal'
		AND p.deleted_at IS NULL AND p.type <> 'market'
		AND c.publication_status = 'published' AND c.moderation_status = 'normal'
		AND c.deleted_at IS NULL AND c.author_id <> p.author_id`
	having := ""
	if rawCursor != "" {
		createdAt, id, err := decodeProfileCursor(rawCursor)
		if err != nil {
			return "", nil, err
		}
		having = "HAVING (MAX(c.created_at), p.id) < ($2, $3)"
		args = append(args, createdAt, id)
	}
	args = append(args, limit+1)
	return fmt.Sprintf(`
		SELECT p.id, p.author_id, u.username, COALESCE(up.nickname, u.username), COALESCE(up.level, 1),
		       p.community_id, cm.slug, cm.name, p.type, p.title, p.content,
		       p.comment_count, p.like_count, p.bookmark_count, p.share_count, p.view_count,
		       p.created_at, p.updated_at, COALESCE(p.published_at, p.created_at), MAX(c.created_at) AS latest_comment_at
		FROM posts p
		JOIN users u ON u.id = p.author_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		JOIN comments c ON c.post_id = p.id
		JOIN communities cm ON cm.id = p.community_id
		WHERE %s
		GROUP BY p.id, p.author_id, u.username, up.nickname, up.level, p.community_id,
		         cm.slug, cm.name, p.type, p.title, p.content, p.comment_count,
		         p.like_count, p.bookmark_count, p.share_count, p.view_count,
		         p.created_at, p.updated_at, p.published_at
		%s
		ORDER BY latest_comment_at DESC, p.id DESC
		LIMIT $%d`, where, having, len(args)), args, nil
}

func profilePostItemMap(row postResponse, activityAt *time.Time) map[string]any {
	encoded, _ := json.Marshal(row)
	item := map[string]any{}
	_ = json.Unmarshal(encoded, &item)
	if activityAt != nil {
		item["activity_at"] = activityAt
	}
	return item
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
	if err := s.db.QueryRowContext(r.Context(), `SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND type <> 'market' AND deleted_at IS NULL`, postID).Scan(&exists); err == sql.ErrNoRows {
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
