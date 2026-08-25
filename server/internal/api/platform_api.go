package api

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrBlockTargetNotFound  = errors.New("block target not found")
	ErrBlocked              = errors.New("blocked by user")
	ErrInvalidReport        = errors.New("invalid report")
	ErrReportTargetNotFound = errors.New("report target not found")
	ErrNotificationNotFound = errors.New("notification not found")
	ErrInvalidSearchCursor  = errors.New("invalid search cursor")
)

func usersBlockEachOther(ctx context.Context, db *sql.DB, firstUserID, secondUserID string) (bool, error) {
	var blocked bool
	err := db.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1))`, firstUserID, secondUserID).Scan(&blocked)
	return blocked, err
}

type notificationCursor struct {
	CreatedAt time.Time `json:"created_at"`
	ID        string    `json:"id"`
	Category  string    `json:"category"`
}

type searchCursor struct {
	Kind      string    `json:"kind"`
	Rank      float64   `json:"rank"`
	SortOrder int       `json:"sort_order,omitempty"`
	CreatedAt time.Time `json:"created_at,omitempty"`
	ID        string    `json:"id"`
}

type searchPage struct {
	Items      []map[string]any
	NextCursor string
	HasMore    bool
}

func parseNotificationCategory(value string) (string, error) {
	if value == "" {
		return "all", nil
	}
	switch value {
	case "all", "interaction", "community", "moderation", "reply", "like", "system":
		return value, nil
	default:
		return "", errors.New("invalid notification category")
	}
}

func (s *Server) listNotifications(w http.ResponseWriter, r *http.Request) {
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
	category, err := parseNotificationCategory(strings.TrimSpace(r.URL.Query().Get("category")))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CATEGORY", Message: "通知分类无效"})
		return
	}
	var cursor *notificationCursor
	if raw := r.URL.Query().Get("cursor"); raw != "" {
		decoded, decodeErr := decodeNotificationCursor(raw)
		if decodeErr != nil || decoded.Category != category {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		cursor = &decoded
	}
	query := `
		SELECT n.id, n.type, COALESCE(n.actor_id, ''), COALESCE(u.username, ''), COALESCE(up.nickname, ''),
		       n.target_type, n.target_id, n.target_data, n.is_read, n.created_at, n.read_at
		FROM notifications n
		LEFT JOIN users u ON u.id = n.actor_id
		LEFT JOIN user_profiles up ON up.user_id = n.actor_id
		WHERE n.user_id = $1
		  AND (n.actor_id IS NULL OR NOT EXISTS (
			SELECT 1 FROM blocks b
			WHERE (b.blocker_id = n.user_id AND b.blocked_id = n.actor_id)
			   OR (b.blocker_id = n.actor_id AND b.blocked_id = n.user_id)
		  ))`
	args := []any{user.ID}
	const replyTypes = "'reply', 'comment.created', 'comment.replied'"
	const interactionTypes = "'like', 'bookmark', 'follow', 'post.liked', 'post.bookmarked', 'user.followed'"
	const communityTypes = "'announcement', 'event', 'maintenance', 'community.announcement', 'community.event', 'community.maintenance', 'rules.updated'"
	const moderationTypes = "'moderation.action', 'appeal.result'"
	switch category {
	case "interaction":
		query += " AND n.type IN (" + replyTypes + ", " + interactionTypes + ")"
	case "community":
		query += " AND n.type IN (" + communityTypes + ")"
	case "moderation":
		query += " AND n.type IN (" + moderationTypes + ")"
	case "reply":
		query += " AND n.type IN (" + replyTypes + ")"
	case "like":
		query += " AND n.type IN (" + interactionTypes + ")"
	case "system":
		query += " AND n.type NOT IN (" + replyTypes + ", " + interactionTypes + ")"
	}
	if cursor != nil {
		query += " AND (n.created_at, n.id) < ($2, $3)"
		args = append(args, cursor.CreatedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	query += fmt.Sprintf(" ORDER BY n.created_at DESC, n.id DESC LIMIT $%d", limitPosition)
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	type notificationResponse struct {
		ID         string         `json:"id"`
		Type       string         `json:"type"`
		Actor      userSummary    `json:"actor"`
		TargetType string         `json:"target_type"`
		TargetID   string         `json:"target_id"`
		TargetData map[string]any `json:"target_data,omitempty"`
		IsRead     bool           `json:"is_read"`
		CreatedAt  time.Time      `json:"created_at"`
		ReadAt     *time.Time     `json:"read_at,omitempty"`
	}
	items := make([]notificationResponse, 0, limit+1)
	for rows.Next() {
		var item notificationResponse
		var actorID sql.NullString
		var rawTargetData []byte
		var readAt sql.NullTime
		if err := rows.Scan(&item.ID, &item.Type, &actorID, &item.Actor.Username, &item.Actor.Nickname, &item.TargetType, &item.TargetID, &rawTargetData, &item.IsRead, &item.CreatedAt, &readAt); err != nil {
			// actor_id 是 text，使用独立字符串扫描，避免 NULL 参与时间类型扫描。
			writeInternalError(w, r, err)
			return
		}
		item.Actor.ID = actorID.String
		if len(rawTargetData) > 0 {
			if err := json.Unmarshal(rawTargetData, &item.TargetData); err != nil {
				writeInternalError(w, r, err)
				return
			}
		}
		if readAt.Valid {
			item.ReadAt = &readAt.Time
		}
		items = append(items, item)
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
		encoded, encodeErr := encodeNotificationCursor(notificationCursor{CreatedAt: items[len(items)-1].CreatedAt, ID: items[len(items)-1].ID, Category: category})
		if encodeErr != nil {
			writeInternalError(w, r, encodeErr)
			return
		}
		nextCursor = encoded
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func (s *Server) markNotificationRead(w http.ResponseWriter, r *http.Request, notificationID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	result, err := s.db.ExecContext(r.Context(), `UPDATE notifications SET is_read = true, read_at = COALESCE(read_at, now()) WHERE id = $1 AND user_id = $2`, notificationID, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	affected, err := result.RowsAffected()
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if affected == 0 {
		writeAuthError(w, r, ErrNotificationNotFound)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": notificationID, "is_read": true})
}

func (s *Server) markAllNotificationsRead(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if _, err := s.db.ExecContext(r.Context(), `UPDATE notifications SET is_read = true, read_at = COALESCE(read_at, now()) WHERE user_id = $1 AND is_read = false`, user.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"is_read": true})
}

func (s *Server) unreadNotificationCount(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var count int64
	if err := s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM notifications WHERE user_id = $1 AND is_read = false`, user.ID).Scan(&count); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"unread_count": count})
}

func (s *Server) search(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	searchType := r.URL.Query().Get("type")
	if query == "" || len([]rune(query)) > 100 {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_QUERY", Message: "搜索关键词不合法"})
		return
	}
	if searchType == "" {
		searchType = "all"
	}
	if searchType != "all" && searchType != "posts" && searchType != "users" && searchType != "communities" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_SEARCH_TYPE", Message: "搜索类型不支持"})
		return
	}
	rawCursor := strings.TrimSpace(r.URL.Query().Get("cursor"))
	if rawCursor != "" && searchType == "all" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "综合搜索请先选择帖子、用户或板块分类"})
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 无效"})
		return
	}
	response := map[string]any{}
	var nextCursor any
	var hasMore bool
	if searchType == "all" || searchType == "posts" {
		page, queryErr := s.searchPosts(r, query, limit, rawCursor)
		if queryErr != nil {
			if errors.Is(queryErr, ErrInvalidSearchCursor) {
				httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			} else {
				writeInternalError(w, r, queryErr)
			}
			return
		}
		response["posts"] = page.Items
		if searchType == "posts" {
			nextCursor = nullableSearchCursor(page)
			hasMore = page.HasMore
		}
	}
	if searchType == "all" || searchType == "users" {
		page, queryErr := s.searchUsers(r, query, limit, rawCursor)
		if queryErr != nil {
			if errors.Is(queryErr, ErrInvalidSearchCursor) {
				httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			} else {
				writeInternalError(w, r, queryErr)
			}
			return
		}
		response["users"] = page.Items
		if searchType == "users" {
			nextCursor = nullableSearchCursor(page)
			hasMore = page.HasMore
		}
	}
	if searchType == "all" || searchType == "communities" {
		page, queryErr := s.searchCommunities(r, query, limit, rawCursor)
		if queryErr != nil {
			if errors.Is(queryErr, ErrInvalidSearchCursor) {
				httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			} else {
				writeInternalError(w, r, queryErr)
			}
			return
		}
		response["communities"] = page.Items
		if searchType == "communities" {
			nextCursor = nullableSearchCursor(page)
			hasMore = page.HasMore
		}
	}
	response["next_cursor"] = nextCursor
	response["has_more"] = hasMore
	httpserver.WriteJSON(w, http.StatusOK, response)
}

func (s *Server) searchPosts(r *http.Request, query string, limit int, rawCursor string) (searchPage, error) {
	rankExpression := "ts_rank(p.search_vector, plainto_tsquery('simple', $1))"
	args := []any{query}
	where := `p.search_vector @@ plainto_tsquery('simple', $1)
		  AND p.publication_status = 'published' AND p.moderation_status = 'normal' AND p.deleted_at IS NULL AND p.type <> 'market'`
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		where += fmt.Sprintf(" AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = $%d AND b.blocked_id = p.author_id) OR (b.blocker_id = p.author_id AND b.blocked_id = $%d))", len(args)+1, len(args)+1)
		args = append(args, viewer.ID)
	}
	if rawCursor != "" {
		cursor, err := decodeSearchCursor(rawCursor)
		if err != nil {
			return searchPage{}, err
		}
		if cursor.Kind != "" && cursor.Kind != "posts" {
			return searchPage{}, ErrInvalidSearchCursor
		}
		where += fmt.Sprintf(" AND (%s, p.created_at, p.id) < ($%d, $%d, $%d)", rankExpression, len(args)+1, len(args)+2, len(args)+3)
		args = append(args, cursor.Rank, cursor.CreatedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT p.id, p.title, LEFT(p.content, 200), p.community_id, c.name, p.created_at,
		       `+rankExpression+`
		FROM posts p
		JOIN communities c ON c.id = p.community_id
		WHERE `+where+`
		ORDER BY `+rankExpression+` DESC, p.created_at DESC, p.id DESC
		LIMIT $`+strconv.Itoa(limitPosition), args...)
	if err != nil {
		return searchPage{}, err
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	for rows.Next() {
		var id, title, preview, communityID, communityName string
		var createdAt time.Time
		var rank float64
		if err := rows.Scan(&id, &title, &preview, &communityID, &communityName, &createdAt, &rank); err != nil {
			return searchPage{}, err
		}
		items = append(items, map[string]any{"id": id, "title": title, "content_preview": preview, "community_id": communityID, "community_name": communityName, "created_at": createdAt, "rank": rank})
	}
	if err := rows.Err(); err != nil {
		return searchPage{}, err
	}
	page := searchPage{Items: items, HasMore: len(items) > limit}
	if page.HasMore {
		page.Items = page.Items[:limit]
		last := page.Items[len(page.Items)-1]
		page.NextCursor, _ = encodeSearchCursor(searchCursor{Kind: "posts", Rank: last["rank"].(float64), CreatedAt: last["created_at"].(time.Time), ID: last["id"].(string)})
	}
	return page, nil
}

func (s *Server) searchUsers(r *http.Request, query string, limit int, rawCursor string) (searchPage, error) {
	rankExpression := "ts_rank(u.search_vector, plainto_tsquery('simple', $1))"
	args := []any{query}
	where := `u.search_vector @@ plainto_tsquery('simple', $1) AND u.status = 'active' AND u.deleted_at IS NULL`
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		where += fmt.Sprintf(" AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = $%d AND b.blocked_id = u.id) OR (b.blocker_id = u.id AND b.blocked_id = $%d))", len(args)+1, len(args)+1)
		args = append(args, viewer.ID)
	}
	if rawCursor != "" {
		cursor, err := decodeSearchCursor(rawCursor)
		if err != nil {
			return searchPage{}, err
		}
		if cursor.Kind != "" && cursor.Kind != "users" {
			return searchPage{}, ErrInvalidSearchCursor
		}
		where += fmt.Sprintf(" AND (%s < $%d OR (%s = $%d AND u.id > $%d))", rankExpression, len(args)+1, rankExpression, len(args)+1, len(args)+2)
		args = append(args, cursor.Rank, cursor.ID)
	}
	limitPosition := len(args) + 1
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT u.id, u.username, COALESCE(up.nickname, u.username), u.created_at,
		       `+rankExpression+`
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE `+where+`
		ORDER BY `+rankExpression+` DESC, u.id ASC
		LIMIT $`+strconv.Itoa(limitPosition), args...)
	if err != nil {
		return searchPage{}, err
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	for rows.Next() {
		var id, username, nickname string
		var createdAt time.Time
		var rank float64
		if err := rows.Scan(&id, &username, &nickname, &createdAt, &rank); err != nil {
			return searchPage{}, err
		}
		items = append(items, map[string]any{"id": id, "username": username, "nickname": nickname, "created_at": createdAt, "rank": rank})
	}
	if err := rows.Err(); err != nil {
		return searchPage{}, err
	}
	page := searchPage{Items: items, HasMore: len(items) > limit}
	if page.HasMore {
		page.Items = page.Items[:limit]
		last := page.Items[len(page.Items)-1]
		page.NextCursor, _ = encodeSearchCursor(searchCursor{Kind: "users", Rank: last["rank"].(float64), ID: last["id"].(string)})
	}
	return page, nil
}

func (s *Server) searchCommunities(r *http.Request, query string, limit int, rawCursor string) (searchPage, error) {
	rankExpression := "ts_rank(c.search_vector, plainto_tsquery('simple', $1))"
	args := []any{query}
	where := `c.search_vector @@ plainto_tsquery('simple', $1) AND c.status = 'active' AND c.deleted_at IS NULL`
	if rawCursor != "" {
		cursor, err := decodeSearchCursor(rawCursor)
		if err != nil {
			return searchPage{}, err
		}
		if cursor.Kind != "" && cursor.Kind != "communities" {
			return searchPage{}, ErrInvalidSearchCursor
		}
		where += fmt.Sprintf(" AND (%s < $%d OR (%s = $%d AND (c.sort_order > $%d OR (c.sort_order = $%d AND c.id > $%d))))", rankExpression, len(args)+1, rankExpression, len(args)+1, len(args)+2, len(args)+2, len(args)+3)
		args = append(args, cursor.Rank, cursor.SortOrder, cursor.ID)
	}
	limitPosition := len(args) + 1
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT c.id, c.slug, c.name, c.description, c.post_count, c.follower_count, c.sort_order,
		       `+rankExpression+`
		FROM communities c
		WHERE `+where+`
		ORDER BY `+rankExpression+` DESC, c.sort_order ASC, c.id ASC
		LIMIT $`+strconv.Itoa(limitPosition), args...)
	if err != nil {
		return searchPage{}, err
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	for rows.Next() {
		var id, slug, name, description string
		var postCount, followerCount int64
		var sortOrder int
		var rank float64
		if err := rows.Scan(&id, &slug, &name, &description, &postCount, &followerCount, &sortOrder, &rank); err != nil {
			return searchPage{}, err
		}
		items = append(items, map[string]any{"id": id, "slug": slug, "name": name, "description": description, "post_count": postCount, "follower_count": followerCount, "sort_order": sortOrder, "rank": rank})
	}
	if err := rows.Err(); err != nil {
		return searchPage{}, err
	}
	page := searchPage{Items: items, HasMore: len(items) > limit}
	if page.HasMore {
		page.Items = page.Items[:limit]
		last := page.Items[len(page.Items)-1]
		page.NextCursor, _ = encodeSearchCursor(searchCursor{Kind: "communities", Rank: last["rank"].(float64), SortOrder: last["sort_order"].(int), ID: last["id"].(string)})
	}
	return page, nil
}

func encodeSearchCursor(cursor searchCursor) (string, error) {
	data, err := json.Marshal(cursor)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func decodeSearchCursor(value string) (searchCursor, error) {
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return searchCursor{}, fmt.Errorf("%w: %v", ErrInvalidSearchCursor, err)
	}
	var cursor searchCursor
	if err := json.Unmarshal(data, &cursor); err != nil || cursor.ID == "" {
		return searchCursor{}, ErrInvalidSearchCursor
	}
	return cursor, nil
}

func nullableSearchCursor(page searchPage) any {
	if page.NextCursor == "" {
		return nil
	}
	return page.NextCursor
}

type reportInput struct {
	TargetType  string `json:"target_type"`
	TargetID    string `json:"target_id"`
	ReasonCode  string `json:"reason_code"`
	Description string `json:"description"`
}

func (s *Server) createReport(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var input reportInput
	if err := decodeJSON(r, &input); err != nil || !validReportInput(input) {
		writeAuthError(w, r, ErrInvalidReport)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if err := ensureReportTarget(r.Context(), tx, input.TargetType, input.TargetID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	now := time.Now().UTC()
	reportID := newPostID()
	caseID := newPostID()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO reports (id, reporter_id, target_type, target_id, reason_code, description, status, created_at) VALUES ($1, $2, $3, $4, $5, $6, 'pending', $7)`, reportID, user.ID, input.TargetType, input.TargetID, input.ReasonCode, strings.TrimSpace(input.Description), now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO moderation_cases (id, target_type, target_id, source, risk_level, status, created_at) VALUES ($1, $2, $3, 'user_report', 'low', 'open', $4)`, caseID, input.TargetType, input.TargetID, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := enqueueOutboxTx(tx, "moderation.case.created", "moderation_case", caseID, map[string]any{
		"report_id":   reportID,
		"target_type": input.TargetType,
		"target_id":   input.TargetID,
	}, now); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, map[string]any{"id": reportID, "moderation_case_id": caseID, "status": "pending"})
}

func ensureReportTarget(ctx context.Context, tx *sql.Tx, targetType, targetID string) error {
	var query string
	switch targetType {
	case "post":
		query = `SELECT id FROM posts WHERE id = $1 AND deleted_at IS NULL`
	case "comment":
		query = `SELECT id FROM comments WHERE id = $1 AND deleted_at IS NULL`
	case "user":
		query = `SELECT id FROM users WHERE id = $1 AND deleted_at IS NULL`
	case "community":
		query = `SELECT id FROM communities WHERE id = $1 AND deleted_at IS NULL`
	default:
		return ErrInvalidReport
	}
	var id string
	err := tx.QueryRowContext(ctx, query, targetID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrReportTargetNotFound
	}
	return err
}

func validReportInput(input reportInput) bool {
	if strings.TrimSpace(input.TargetID) == "" || strings.TrimSpace(input.ReasonCode) == "" || len([]rune(input.Description)) > 2000 {
		return false
	}
	switch input.TargetType {
	case "post", "comment", "user", "community":
		return true
	default:
		return false
	}
}

func (s *Server) toggleBlock(w http.ResponseWriter, r *http.Request, targetUserID string, active bool) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if targetUserID == "" || targetUserID == user.ID {
		writeAuthError(w, r, ErrBlockTargetNotFound)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if err := lockUserForInteraction(r.Context(), tx, targetUserID); err != nil {
		if errors.Is(err, ErrInteractionTargetNotFound) {
			err = ErrBlockTargetNotFound
		}
		writeAuthError(w, r, err)
		return
	}
	if active {
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT (blocker_id, blocked_id) DO NOTHING`, user.ID, targetUserID); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if _, err := tx.ExecContext(r.Context(), `DELETE FROM user_follows WHERE (follower_id = $1 AND followee_id = $2) OR (follower_id = $2 AND followee_id = $1)`, user.ID, targetUserID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	} else if _, err := tx.ExecContext(r.Context(), `DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2`, user.ID, targetUserID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active})
}

func encodeNotificationCursor(cursor notificationCursor) (string, error) {
	data, err := json.Marshal(cursor)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func decodeNotificationCursor(value string) (notificationCursor, error) {
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return notificationCursor{}, err
	}
	var cursor notificationCursor
	if err := json.Unmarshal(data, &cursor); err != nil || cursor.ID == "" || cursor.CreatedAt.IsZero() {
		return notificationCursor{}, errors.New("invalid notification cursor")
	}
	// 兼容旧版“全部”列表游标；分类游标始终和分类绑定，不能串用。
	if cursor.Category == "" {
		cursor.Category = "all"
	}
	if _, err := parseNotificationCategory(cursor.Category); err != nil {
		return notificationCursor{}, errors.New("invalid notification cursor")
	}
	return cursor, nil
}
