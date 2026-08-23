package api

import (
	"fmt"
	"net/http"
	"strconv"
	"time"

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
	ID             string              `json:"id"`
	Author         userSummary         `json:"author"`
	Community      communitySummary    `json:"community"`
	Type           string              `json:"type"`
	Title          string              `json:"title"`
	Content        string              `json:"content,omitempty"`
	ContentPreview string              `json:"content_preview,omitempty"`
	CommentCount   int64               `json:"comment_count"`
	LikeCount      int64               `json:"like_count"`
	BookmarkCount  int64               `json:"bookmark_count,omitempty"`
	ShareCount     int64               `json:"share_count,omitempty"`
	ViewCount      int64               `json:"view_count"`
	CreatedAt      time.Time           `json:"created_at"`
	UpdatedAt      time.Time           `json:"updated_at,omitempty"`
	PublishedAt    *time.Time          `json:"published_at,omitempty"`
	Publication    string              `json:"publication_status,omitempty"`
	Moderation     string              `json:"moderation_status,omitempty"`
	Media          []postMediaResponse `json:"media,omitempty"`
	ViewerState    *viewerPostState    `json:"viewer_state,omitempty"`
}

type feedPostRow struct {
	post        postResponse
	publishedAt time.Time
	score       *float64
}

// feedSortColumns 返回 feed 排序对应的评分表达式与 ORDER BY 片段。
// scoreExpr 为空表示按发布时间排序（latest），游标不携带评分；
// 否则游标携带 (score, published_at, id) 三元组做键集分页。
func feedSortColumns(sort string) (scoreExpr, orderBy string) {
	ageHours := "EXTRACT(EPOCH FROM (now() - p.published_at)) / 3600.0"
	switch sort {
	case "recommended":
		scoreExpr = "(p.like_count * 4 + p.comment_count * 3 + p.bookmark_count * 5 + p.share_count * 2 + p.view_count * 0.05) / POWER(" + ageHours + " + 2, 1.25)"
	case "hot":
		scoreExpr = "(p.like_count + p.comment_count + 2 * p.bookmark_count + p.share_count) / POWER(" + ageHours + " + 2, 1.5)"
	case "featured":
		scoreExpr = "p.bookmark_count * 5 + p.like_count * 3 + p.comment_count * 2 + p.share_count * 2"
	default:
		return "", "ORDER BY p.published_at DESC, p.id DESC"
	}
	return scoreExpr, "ORDER BY (" + scoreExpr + ") DESC, p.published_at DESC, p.id DESC"
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
	scoreExpr, orderBy := feedSortColumns(r.URL.Query().Get("sort"))
	scored := scoreExpr != ""
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
		cursor = &decoded
	}

	columns := `
		SELECT p.id, p.author_id, u.username, COALESCE(up.nickname, u.username), p.community_id, c.slug, c.name,
		       p.type, p.title, p.content, p.comment_count, p.like_count, p.bookmark_count, p.share_count, p.view_count,
		       p.created_at, p.updated_at, p.published_at`
	if scored {
		columns += ", " + scoreExpr + " AS feed_score"
	}
	query := columns + `
		FROM posts p
		JOIN users u ON u.id = p.author_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		JOIN communities c ON c.id = p.community_id
		WHERE p.publication_status = 'published' AND p.moderation_status = 'normal'
		  AND p.deleted_at IS NULL AND p.published_at IS NOT NULL
		  AND c.status = 'active' AND c.deleted_at IS NULL`
	args := make([]any, 0, 4)
	if cursor != nil {
		if scored {
			score := 0.0
			if cursor.Score != nil {
				score = *cursor.Score
			}
			query += " AND (" + scoreExpr + ", p.published_at, p.id) < ($1, $2, $3)"
			args = append(args, score, cursor.PublishedAt, cursor.ID)
		} else {
			query += " AND (p.published_at, p.id) < ($1, $2)"
			args = append(args, cursor.PublishedAt, cursor.ID)
		}
	}
	if communityID := r.URL.Query().Get("community_id"); communityID != "" {
		query += fmt.Sprintf(" AND p.community_id = $%d", len(args)+1)
		args = append(args, communityID)
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
		destinations := []any{
			&row.post.ID, &row.post.Author.ID, &row.post.Author.Username, &row.post.Author.Nickname,
			&row.post.Community.ID, &row.post.Community.Slug, &row.post.Community.Name, &row.post.Type,
			&row.post.Title, &row.post.ContentPreview, &row.post.CommentCount, &row.post.LikeCount,
			&row.post.BookmarkCount, &row.post.ShareCount, &row.post.ViewCount, &row.post.CreatedAt,
			&row.post.UpdatedAt, &row.publishedAt,
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
		next := feedCursor{PublishedAt: last.publishedAt, ID: last.post.ID}
		if scored {
			next.Score = last.score
		}
		nextCursor, err = encodeFeedCursor(next)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nullableString(nextCursor), "has_more": hasMore})
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
