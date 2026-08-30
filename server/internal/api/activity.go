package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

type activityResponse struct {
	ID           string     `json:"id"`
	Title        string     `json:"title"`
	Description  string     `json:"description"`
	CoverMediaID string     `json:"cover_media_id,omitempty"`
	CoverURL     string     `json:"cover_url,omitempty"`
	StartAt      *time.Time `json:"start_at,omitempty"`
	EndAt        *time.Time `json:"end_at,omitempty"`
	Location     string     `json:"location,omitempty"`
	Status       string     `json:"status"`
	CreatedBy    string     `json:"created_by"`
	AuthorName   string     `json:"author_name,omitempty"`
	PublishedAt  *time.Time `json:"published_at,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

type createActivityInput struct {
	Title        string     `json:"title"`
	Description  string     `json:"description"`
	CoverMediaID string     `json:"cover_media_id"`
	CoverURL     string     `json:"cover_url"`
	StartAt      *time.Time `json:"start_at"`
	EndAt        *time.Time `json:"end_at"`
	Location     string     `json:"location"`
	Status       string     `json:"status"`
}

// listAdminActivities 管理员查看活动列表（支持状态筛选）。
func (s *Server) listAdminActivities(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok || !s.hasAnyPermission(r, user.ID, "moderation.action") {
		if ok {
			writeAuthError(w, r, ErrPermissionDenied)
		}
		return
	}

	statusFilter := strings.TrimSpace(r.URL.Query().Get("status"))

	query := `
		SELECT a.id, a.title, a.description, COALESCE(a.cover_media_id, ''),
		       COALESCE(ma.object_key, a.cover_url, ''),
		       a.start_at, a.end_at, a.location, a.status, a.created_by,
		       COALESCE(up.nickname, u.username, ''), a.published_at, a.created_at, a.updated_at
		FROM activities a
		JOIN users u ON u.id = a.created_by
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets ma ON ma.id = a.cover_media_id AND ma.deleted_at IS NULL
		WHERE a.deleted_at IS NULL`

	args := make([]any, 0, 2)
	if statusFilter != "" && statusFilter != "all" {
		args = append(args, statusFilter)
		query += " AND a.status = $1"
	}
	query += " ORDER BY a.created_at DESC LIMIT 100"

	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()

	items := make([]activityResponse, 0)
	for rows.Next() {
		var item activityResponse
		var coverMediaID, coverKey string
		var startAt, endAt, publishedAt sql.NullTime
		if err := rows.Scan(
			&item.ID, &item.Title, &item.Description, &coverMediaID,
			&coverKey, &startAt, &endAt, &item.Location, &item.Status,
			&item.CreatedBy, &item.AuthorName, &publishedAt, &item.CreatedAt, &item.UpdatedAt,
		); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if coverMediaID != "" {
			item.CoverMediaID = coverMediaID
		}
		if coverKey != "" {
			item.CoverURL = publicMediaURL(coverKey)
		}
		if startAt.Valid {
			item.StartAt = &startAt.Time
		}
		if endAt.Valid {
			item.EndAt = &endAt.Time
		}
		if publishedAt.Valid {
			item.PublishedAt = &publishedAt.Time
		}
		items = append(items, item)
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

// createAdminActivity 管理员创建活动。
func (s *Server) createAdminActivity(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok || !s.hasAnyPermission(r, user.ID, "moderation.action") {
		if ok {
			writeAuthError(w, r, ErrPermissionDenied)
		}
		return
	}

	var input createActivityInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusBadRequest,
			Code:    "INVALID_REQUEST",
			Message: "活动数据格式错误",
		})
		return
	}

	title := strings.TrimSpace(input.Title)
	if title == "" {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusBadRequest,
			Code:    "INVALID_TITLE",
			Message: "活动标题不能为空",
		})
		return
	}

	status := strings.TrimSpace(input.Status)
	if status == "" {
		status = "draft"
	}
	switch status {
	case "draft", "upcoming", "active", "ended", "offline":
	default:
		status = "draft"
	}

	var publishedAt *time.Time
	if status == "active" || status == "upcoming" {
		now := time.Now().UTC()
		publishedAt = &now
	}

	activityID := newPostID()
	coverMediaID := strings.TrimSpace(input.CoverMediaID)
	coverURL := strings.TrimSpace(input.CoverURL)

	_, err := s.db.ExecContext(r.Context(), `
		INSERT INTO activities (
			id, title, description, cover_media_id, cover_url,
			start_at, end_at, location, status, created_by, published_at, created_at, updated_at
		) VALUES (
			$1, $2, $3, NULLIF($4, ''), $5,
			$6, $7, $8, $9, $10, $11, now(), now()
		)`,
		activityID, title, strings.TrimSpace(input.Description), coverMediaID, coverURL,
		input.StartAt, input.EndAt, strings.TrimSpace(input.Location), status, user.ID, publishedAt,
	)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	httpserver.WriteJSON(w, http.StatusCreated, map[string]any{
		"id":      activityID,
		"status":  status,
		"message": "活动已创建",
	})
}

// updateAdminActivity 管理员更新活动。
func (s *Server) updateAdminActivity(w http.ResponseWriter, r *http.Request, activityID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok || !s.hasAnyPermission(r, user.ID, "moderation.action") {
		if ok {
			writeAuthError(w, r, ErrPermissionDenied)
		}
		return
	}

	var input createActivityInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusBadRequest,
			Code:    "INVALID_REQUEST",
			Message: "活动数据格式错误",
		})
		return
	}

	title := strings.TrimSpace(input.Title)
	if title == "" {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusBadRequest,
			Code:    "INVALID_TITLE",
			Message: "活动标题不能为空",
		})
		return
	}

	status := strings.TrimSpace(input.Status)
	if status == "" {
		status = "draft"
	}

	coverMediaID := strings.TrimSpace(input.CoverMediaID)
	coverURL := strings.TrimSpace(input.CoverURL)

	res, err := s.db.ExecContext(r.Context(), `
		UPDATE activities
		SET title = $1, description = $2, cover_media_id = NULLIF($3, ''), cover_url = $4,
		    start_at = $5, end_at = $6, location = $7, status = $8, updated_at = now()
		WHERE id = $9 AND deleted_at IS NULL`,
		title, strings.TrimSpace(input.Description), coverMediaID, coverURL,
		input.StartAt, input.EndAt, strings.TrimSpace(input.Location), status, activityID,
	)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusNotFound,
			Code:    "ACTIVITY_NOT_FOUND",
			Message: "活动不存在或已被删除",
		})
		return
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": activityID, "status": status, "message": "活动已更新"})
}

// publishAdminActivity 发布活动（status -> active / upcoming）。
func (s *Server) publishAdminActivity(w http.ResponseWriter, r *http.Request, activityID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok || !s.hasAnyPermission(r, user.ID, "moderation.action") {
		if ok {
			writeAuthError(w, r, ErrPermissionDenied)
		}
		return
	}

	var startAt sql.NullTime
	err := s.db.QueryRowContext(r.Context(), `SELECT start_at FROM activities WHERE id = $1 AND deleted_at IS NULL`, activityID).Scan(&startAt)
	if errors.Is(err, sql.ErrNoRows) {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusNotFound,
			Code:    "ACTIVITY_NOT_FOUND",
			Message: "活动不存在",
		})
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}

	newStatus := "active"
	if startAt.Valid && startAt.Time.After(time.Now().UTC()) {
		newStatus = "upcoming"
	}

	_, err = s.db.ExecContext(r.Context(), `
		UPDATE activities
		SET status = $1, published_at = COALESCE(published_at, now()), updated_at = now()
		WHERE id = $2 AND deleted_at IS NULL`, newStatus, activityID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": activityID, "status": newStatus, "message": "活动已发布"})
}

// offlineAdminActivity 下架活动（status -> offline）。
func (s *Server) offlineAdminActivity(w http.ResponseWriter, r *http.Request, activityID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok || !s.hasAnyPermission(r, user.ID, "moderation.action") {
		if ok {
			writeAuthError(w, r, ErrPermissionDenied)
		}
		return
	}

	res, err := s.db.ExecContext(r.Context(), `
		UPDATE activities
		SET status = 'offline', updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL`, activityID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusNotFound,
			Code:    "ACTIVITY_NOT_FOUND",
			Message: "活动不存在",
		})
		return
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": activityID, "status": "offline", "message": "活动已下架"})
}

// deleteAdminActivity 软删除活动。
func (s *Server) deleteAdminActivity(w http.ResponseWriter, r *http.Request, activityID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok || !s.hasAnyPermission(r, user.ID, "moderation.action") {
		if ok {
			writeAuthError(w, r, ErrPermissionDenied)
		}
		return
	}

	res, err := s.db.ExecContext(r.Context(), `
		UPDATE activities
		SET deleted_at = now(), updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL`, activityID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusNotFound,
			Code:    "ACTIVITY_NOT_FOUND",
			Message: "活动不存在",
		})
		return
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": activityID, "message": "活动已删除"})
}

// listPublicActivities 普通用户查看公开活动列表。
func (s *Server) listPublicActivities(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}

	rows, err := s.db.QueryContext(r.Context(), `
		SELECT a.id, a.title, a.description, COALESCE(a.cover_media_id, ''),
		       COALESCE(ma.object_key, a.cover_url, ''),
		       a.start_at, a.end_at, a.location, a.status, a.created_by,
		       COALESCE(up.nickname, u.username, ''), a.published_at, a.created_at, a.updated_at
		FROM activities a
		JOIN users u ON u.id = a.created_by
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets ma ON ma.id = a.cover_media_id AND ma.deleted_at IS NULL
		WHERE a.deleted_at IS NULL AND a.status IN ('upcoming', 'active', 'ended')
		ORDER BY COALESCE(a.start_at, a.published_at, a.created_at) DESC
		LIMIT 50`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()

	items := make([]activityResponse, 0)
	for rows.Next() {
		var item activityResponse
		var coverMediaID, coverKey string
		var startAt, endAt, publishedAt sql.NullTime
		if err := rows.Scan(
			&item.ID, &item.Title, &item.Description, &coverMediaID,
			&coverKey, &startAt, &endAt, &item.Location, &item.Status,
			&item.CreatedBy, &item.AuthorName, &publishedAt, &item.CreatedAt, &item.UpdatedAt,
		); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if coverMediaID != "" {
			item.CoverMediaID = coverMediaID
		}
		if coverKey != "" {
			item.CoverURL = publicMediaURL(coverKey)
		}
		if startAt.Valid {
			item.StartAt = &startAt.Time
		}
		if endAt.Valid {
			item.EndAt = &endAt.Time
		}
		if publishedAt.Valid {
			item.PublishedAt = &publishedAt.Time
		}
		items = append(items, item)
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}
