package api

import (
	"database/sql"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type userSummary struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	Nickname string `json:"nickname"`
	Level    int    `json:"level,omitempty"`
}

type communitySummary struct {
	ID   string `json:"id"`
	Slug string `json:"slug"`
	Name string `json:"name"`
}

type postResponse struct {
	ID                     string              `json:"id"`
	Author                 userSummary         `json:"author"`
	Community              communitySummary    `json:"community"`
	Type                   string              `json:"type"`
	Title                  string              `json:"title"`
	Content                string              `json:"content,omitempty"`
	ContentPreview         string              `json:"content_preview,omitempty"`
	CommentCount           int64               `json:"comment_count"`
	LikeCount              int64               `json:"like_count"`
	BookmarkCount          int64               `json:"bookmark_count,omitempty"`
	ShareCount             int64               `json:"share_count,omitempty"`
	ViewCount              int64               `json:"view_count"`
	CreatedAt              time.Time           `json:"created_at"`
	UpdatedAt              time.Time           `json:"updated_at,omitempty"`
	PublishedAt            *time.Time          `json:"published_at,omitempty"`
	ActivityAt             *time.Time          `json:"activity_at,omitempty"`
	LastCommentAt          *time.Time          `json:"last_comment_at,omitempty"`
	IsRecommended          bool                `json:"is_recommended,omitempty"`
	RecommendationPosition *int                `json:"recommendation_position,omitempty"`
	Publication            string              `json:"publication_status,omitempty"`
	Moderation             string              `json:"moderation_status,omitempty"`
	Media                  []postMediaResponse `json:"media,omitempty"`
	ViewerState            *viewerPostState    `json:"viewer_state,omitempty"`
}

type feedPostRow struct {
	post          postResponse
	publishedAt   time.Time
	score         *float64
	recPosition   *int
	recAt         *time.Time
	lastCommentAt *time.Time
	activityAt    *time.Time
}

// resolveOptionalViewer 解析 Feed 的当前查看者（可选）：未登录或 token 无效
// 时不阻断公开内容读取，仅用于屏蔽过滤等查看者相关逻辑。包级函数便于
// 集成测试注入固定查看者。
var resolveOptionalViewer = func(s *Server, r *http.Request) (auth.User, bool) {
	return s.optionalAuthenticatedUser(r.Context(), r)
}

// feedSortColumns 返回 feed 排序对应的评分表达式与 ORDER BY 片段。
func feedSortColumns(sort string) (scoreExpr, orderBy string) {
	return feedSortColumnsAt(sort, "CURRENT_TIMESTAMP")
}

func feedSortColumnsAt(sort, asOfPlaceholder string) (scoreExpr, orderBy string) {
	ageHours := "EXTRACT(EPOCH FROM (" + asOfPlaceholder + " - p.published_at)) / 3600.0"
	switch sort {
	case "hot":
		scoreExpr = "((p.like_count + p.comment_count + 2 * p.bookmark_count + p.share_count) / POWER(" + ageHours + " + 2, 1.5))::double precision"
		return scoreExpr, "ORDER BY (" + scoreExpr + ") DESC, p.published_at DESC, p.id DESC"
	case "featured":
		scoreExpr = "(p.bookmark_count * 5 + p.like_count * 3 + p.comment_count * 2 + p.share_count * 2)::double precision"
		return scoreExpr, "ORDER BY (" + scoreExpr + ") DESC, p.published_at DESC, p.id DESC"
	case "recommended":
		return "", "ORDER BY hr.position ASC, hr.recommended_at DESC, p.id DESC"
	default:
		return "", "ORDER BY p.published_at DESC, p.id DESC"
	}
}

func (s *Server) latestFeed(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	filter, err := parseFeedFilter(r.URL.Query().Get("post_type"), r.URL.Query().Get("has_media"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_FILTER", Message: "Feed 筛选条件无效"})
		return
	}

	sortMode := r.URL.Query().Get("sort")
	latestBy := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("latest_by")))
	if latestBy == "" {
		latestBy = "comment" // 默认按最新评论/回复时间
	}
	if latestBy != "comment" && latestBy != "post" {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusBadRequest,
			Code:    "INVALID_LATEST_ORDER",
			Message: "latest_by 只能是 comment 或 post",
		})
		return
	}

	isRecommended := sortMode == "recommended"
	scored := sortMode == "hot" || sortMode == "featured"
	isLatestComment := (sortMode == "latest" || sortMode == "") && latestBy == "comment"
	isLatestPost := (sortMode == "latest" || sortMode == "") && latestBy == "post"
	usesAsOf := sortMode == "hot" || isLatestComment

	var cursor *feedCursor
	if value := r.URL.Query().Get("cursor"); value != "" {
		decoded, err := decodeFeedCursor(value)
		if err != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		if scored && decoded.Score == nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 与当前排序不匹配"})
			return
		}
		if isRecommended && (decoded.Position == nil || decoded.RecommendedAt == nil) {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 与当前排序不匹配"})
			return
		}
		if isLatestComment && (decoded.ActivityAt == nil || decoded.AsOf == nil) {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 与当前排序不匹配"})
			return
		}
		if isLatestPost && decoded.PublishedAt.IsZero() {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 与当前排序不匹配"})
			return
		}
		cursor = &decoded
	}

	var feedAsOf time.Time
	if usesAsOf {
		if cursor != nil && cursor.AsOf != nil {
			feedAsOf = cursor.AsOf.UTC()
		} else if err := s.db.QueryRowContext(r.Context(), `SELECT CURRENT_TIMESTAMP`).Scan(&feedAsOf); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	asOfPlaceholder := "CURRENT_TIMESTAMP"
	if usesAsOf {
		asOfPlaceholder = "$1"
	}
	scoreExpr, orderBy := feedSortColumnsAt(sortMode, asOfPlaceholder)

	commentActivityExpr := "SELECT MAX(c.created_at) FROM comments c WHERE c.post_id = p.id AND c.publication_status = 'published' AND c.moderation_status = 'normal' AND c.deleted_at IS NULL"
	if isLatestComment {
		commentActivityExpr += " AND c.created_at <= " + asOfPlaceholder
	}
	lastCommentExpr := "(" + commentActivityExpr + ")"
	activityExpr := "COALESCE(" + lastCommentExpr + ", p.published_at, p.created_at)"

	columns := `
		SELECT p.id, p.author_id, u.username, COALESCE(up.nickname, u.username), p.community_id, c.slug, c.name,
		       p.type, p.title, p.content, p.comment_count, p.like_count, p.bookmark_count, p.share_count, p.view_count,
		       p.created_at, p.updated_at, p.published_at`

	columns += `, hr.position AS rec_position, hr.recommended_at AS rec_at`

	columns += `, ` + lastCommentExpr + ` AS last_comment_at`
	columns += `, ` + activityExpr + ` AS activity_at`

	if scored {
		columns += ", " + scoreExpr + " AS feed_score"
	}

	var query string
	if isRecommended {
		query = columns + `
		FROM home_recommendations hr
		JOIN posts p ON p.id = hr.post_id
		JOIN users u ON u.id = p.author_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		JOIN communities c ON c.id = p.community_id
		WHERE p.publication_status = 'published' AND p.moderation_status = 'normal'
		  AND p.deleted_at IS NULL AND p.published_at IS NOT NULL AND p.type <> 'market'
		  AND c.status = 'active' AND c.deleted_at IS NULL
		  AND (hr.expires_at IS NULL OR hr.expires_at > CURRENT_TIMESTAMP)`
	} else {
		query = columns + `
		FROM posts p
		JOIN users u ON u.id = p.author_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN home_recommendations hr ON hr.post_id = p.id
		  AND (hr.expires_at IS NULL OR hr.expires_at > CURRENT_TIMESTAMP)
		JOIN communities c ON c.id = p.community_id
		WHERE p.publication_status = 'published' AND p.moderation_status = 'normal'
		  AND p.deleted_at IS NULL AND p.published_at IS NOT NULL AND p.type <> 'market'
		  AND c.status = 'active' AND c.deleted_at IS NULL`
	}

	args := make([]any, 0, 8)
	if usesAsOf {
		args = append(args, feedAsOf)
	}

	if cursor != nil {
		if isRecommended {
			p1 := len(args) + 1
			p2 := len(args) + 2
			p3 := len(args) + 3
			query += fmt.Sprintf(" AND (hr.position > $%d OR (hr.position = $%d AND (hr.recommended_at < $%d OR (hr.recommended_at = $%d AND p.id < $%d))))",
				p1, p1, p2, p2, p3)
			args = append(args, *cursor.Position, *cursor.RecommendedAt, cursor.ID)
		} else if scored {
			score := 0.0
			if cursor.Score != nil {
				score = *cursor.Score
			}
			p1 := len(args) + 1
			p2 := len(args) + 2
			p3 := len(args) + 3
			query += fmt.Sprintf(" AND ("+scoreExpr+", p.published_at, p.id) < ($%d, $%d, $%d)", p1, p2, p3)
			args = append(args, score, cursor.PublishedAt, cursor.ID)
		} else if isLatestComment {
			p1 := len(args) + 1
			p2 := len(args) + 2
			query += fmt.Sprintf(" AND ("+activityExpr+", p.id) < ($%d, $%d)", p1, p2)
			args = append(args, *cursor.ActivityAt, cursor.ID)
		} else {
			p1 := len(args) + 1
			p2 := len(args) + 2
			query += fmt.Sprintf(" AND (p.published_at, p.id) < ($%d, $%d)", p1, p2)
			args = append(args, cursor.PublishedAt, cursor.ID)
		}
	}

	if communityID := r.URL.Query().Get("community_id"); communityID != "" {
		query += fmt.Sprintf(" AND p.community_id = $%d", len(args)+1)
		args = append(args, communityID)
	}
	if filter.PostType != "" {
		query += fmt.Sprintf(" AND p.type = $%d", len(args)+1)
		args = append(args, filter.PostType)
	}
	if filter.HasMedia {
		query += " AND EXISTS (SELECT 1 FROM post_media pm WHERE pm.post_id = p.id)"
	}
	// 双向过滤：被屏蔽者不能继续看到屏蔽方的公开内容，屏蔽方也不再看到被屏蔽者。
	if viewer, ok := resolveOptionalViewer(s, r); ok {
		pViewer := len(args) + 1
		query += fmt.Sprintf(" AND NOT EXISTS (SELECT 1 FROM blocks WHERE (blocker_id = $%d AND blocked_id = p.author_id) OR (blocker_id = p.author_id AND blocked_id = $%d))", pViewer, pViewer)
		args = append(args, viewer.ID)
	}

	if isLatestComment {
		orderBy = "ORDER BY " + activityExpr + " DESC, p.id DESC"
	} else if isLatestPost {
		orderBy = "ORDER BY p.published_at DESC, p.id DESC"
	}

	limitPosition := len(args) + 1
	query += " " + orderBy + fmt.Sprintf(" LIMIT $%d", limitPosition)
	args = append(args, limit+1)

	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()

	rowsData := make([]feedPostRow, 0, limit+1)
	for rows.Next() {
		var row feedPostRow
		var recPos sql.NullInt64
		var recAt sql.NullTime
		var lastCommentAt sql.NullTime
		var activityAt sql.NullTime

		destinations := []any{
			&row.post.ID, &row.post.Author.ID, &row.post.Author.Username, &row.post.Author.Nickname,
			&row.post.Community.ID, &row.post.Community.Slug, &row.post.Community.Name, &row.post.Type,
			&row.post.Title, &row.post.ContentPreview, &row.post.CommentCount, &row.post.LikeCount,
			&row.post.BookmarkCount, &row.post.ShareCount, &row.post.ViewCount, &row.post.CreatedAt,
			&row.post.UpdatedAt, &row.publishedAt,
			&recPos, &recAt,
			&lastCommentAt, &activityAt,
		}
		if scored {
			row.score = new(float64)
			destinations = append(destinations, row.score)
		}
		if err := rows.Scan(destinations...); err != nil {
			writeInternalError(w, r, err)
			return
		}
		row.post.ContentPreview = preview(row.post.ContentPreview)
		row.post.PublishedAt = &row.publishedAt
		if recPos.Valid {
			pos := int(recPos.Int64)
			row.recPosition = &pos
			row.post.IsRecommended = true
			row.post.RecommendationPosition = &pos
		}
		if recAt.Valid {
			t := recAt.Time
			row.recAt = &t
		}
		if lastCommentAt.Valid {
			t := lastCommentAt.Time
			row.lastCommentAt = &t
			row.post.LastCommentAt = &t
		}
		if activityAt.Valid {
			t := activityAt.Time
			row.activityAt = &t
			row.post.ActivityAt = &t
		} else {
			row.activityAt = &row.publishedAt
			row.post.ActivityAt = &row.publishedAt
		}

		rowsData = append(rowsData, row)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}

	hasMore := len(rowsData) > limit
	if hasMore {
		rowsData = rowsData[:limit]
	}
	items := make([]postResponse, 0, len(rowsData))
	for _, row := range rowsData {
		if includePostDetails(r) {
			if err := s.enrichPostResponse(r.Context(), r, &row.post, true); err != nil {
				writeInternalError(w, r, err)
				return
			}
		}
		items = append(items, row.post)
	}

	var nextCursor string
	if hasMore && len(rowsData) > 0 {
		last := rowsData[len(rowsData)-1]
		var next feedCursor
		next.ID = last.post.ID
		if isRecommended {
			next.Position = last.recPosition
			next.RecommendedAt = last.recAt
		} else if scored {
			next.PublishedAt = last.publishedAt
			next.Score = last.score
			asOf := feedAsOf
			if usesAsOf {
				next.AsOf = &asOf
			}
		} else if isLatestComment {
			next.ActivityAt = last.activityAt
			asOf := feedAsOf
			next.AsOf = &asOf
		} else {
			next.PublishedAt = last.publishedAt
		}

		nextCursor, err = encodeFeedCursor(next)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nullableString(nextCursor), "has_more": hasMore})
}

type feedFilter struct {
	PostType string
	HasMedia bool
}

func parseFeedFilter(postType, hasMedia string) (feedFilter, error) {
	filter := feedFilter{PostType: strings.TrimSpace(postType)}
	switch filter.PostType {
	case "", "normal", "guide", "question", "game_share", "poll", "activity":
	default:
		return feedFilter{}, fmt.Errorf("invalid post type")
	}
	switch strings.TrimSpace(hasMedia) {
	case "", "false", "0":
	case "true", "1":
		filter.HasMedia = true
	default:
		return feedFilter{}, fmt.Errorf("invalid has_media")
	}
	return filter, nil
}

func parseLimit(value string) (int, error) {
	if value == "" {
		return 20, nil
	}
	limit, err := strconv.Atoi(value)
	if err != nil || limit < 1 || limit > 50 {
		return 0, fmt.Errorf("invalid limit")
	}
	return limit, nil
}

func preview(value string) string {
	runes := []rune(value)
	if len(runes) <= 160 {
		return value
	}
	return string(runes[:160]) + "…"
}

func nullableString(value string) any {
	if value == "" {
		return nil
	}
	return value
}
