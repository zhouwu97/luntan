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
	PublicationStatus string `json:"publication_status"`
	Phase        string     `json:"phase,omitempty"`
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

func validateActivityTimes(startAt, endAt *time.Time) *httpserver.AppError {
	if startAt != nil && endAt != nil {
		if !endAt.After(*startAt) {
			return &httpserver.AppError{
				Status:  http.StatusBadRequest,
				Code:    "INVALID_ACTIVITY_TIME",
				Message: "活动结束时间必须晚于开始时间",
			}
		}
	}
	return nil
}

func validateActivityStatus(status string) (string, *httpserver.AppError) {
	status = strings.TrimSpace(status)
	if status == "" {
		return "draft", nil
	}
	switch status {
	case "draft", "upcoming", "active", "ended", "offline":
		return status, nil
	default:
		return "", &httpserver.AppError{
			Status:  http.StatusBadRequest,
			Code:    "INVALID_ACTIVITY_STATUS",
			Message: "活动状态无效",
		}
	}
}

func activityPublicationStatus(status string) string {
	if status == "draft" || status == "offline" {
		return status
	}
	return "published"
}

func deriveActivityPhase(startAt, endAt *time.Time, now time.Time) string {
	if startAt != nil && now.Before(*startAt) {
		return "upcoming"
	}
	if endAt != nil && !now.Before(*endAt) {
		return "ended"
	}
	return "active"
}

func activityPhaseForPublication(publicationStatus string, startAt, endAt *time.Time, now time.Time) string {
	if publicationStatus != "published" {
		return ""
	}
	return deriveActivityPhase(startAt, endAt, now)
}

func activityStatusForResponse(publicationStatus string, startAt, endAt *time.Time, now time.Time) string {
	if publicationStatus == "draft" || publicationStatus == "offline" {
		return publicationStatus
	}
	return deriveActivityPhase(startAt, endAt, now)
}

func nullableTime(value sql.NullTime) *time.Time {
	if !value.Valid {
		return nil
	}
	return &value.Time
}

// deriveActivityStatus 保留旧调用方的语义，但内部统一先区分发布状态和
// 时间阶段，避免把一个 status 同时当作持久化状态和动态状态。
func deriveActivityStatus(status string, startAt, endAt *time.Time, now time.Time) string {
	return activityStatusForResponse(activityPublicationStatus(status), startAt, endAt, now)
}

func hydrateActivityStatus(item *activityResponse, now time.Time) {
	if item.PublicationStatus == "" {
		// 兼容迁移前的内存数据和旧测试夹具；正式数据库由新迁移保证该列
		// 非空，后续读写均以 publication_status 为准。
		item.PublicationStatus = activityPublicationStatus(item.Status)
	}
	item.Phase = activityPhaseForPublication(item.PublicationStatus, item.StartAt, item.EndAt, now)
	item.Status = activityStatusForResponse(item.PublicationStatus, item.StartAt, item.EndAt, now)
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
		       a.start_at, a.end_at, a.location, a.publication_status, a.created_by,
		       COALESCE(up.nickname, u.username, ''), a.published_at, a.created_at, a.updated_at
		FROM activities a
		JOIN users u ON u.id = a.created_by
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets ma ON ma.id = a.cover_media_id AND ma.deleted_at IS NULL
		WHERE a.deleted_at IS NULL
		ORDER BY a.created_at DESC
		LIMIT 200`

	rows, err := s.db.QueryContext(r.Context(), query)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()

	now := time.Now().UTC()
	items := make([]activityResponse, 0)
	for rows.Next() {
		var item activityResponse
		var coverMediaID, coverKey string
		var startAt, endAt, publishedAt sql.NullTime
		if err := rows.Scan(
			&item.ID, &item.Title, &item.Description, &coverMediaID,
			&coverKey, &startAt, &endAt, &item.Location, &item.PublicationStatus,
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
		hydrateActivityStatus(&item, now)
		if statusFilter != "" && statusFilter != "all" && item.Status != statusFilter {
			continue
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

	if timeErr := validateActivityTimes(input.StartAt, input.EndAt); timeErr != nil {
		httpserver.WriteAppError(w, r, *timeErr)
		return
	}

	requestedStatus, statusErr := validateActivityStatus(input.Status)
	if statusErr != nil {
		httpserver.WriteAppError(w, r, *statusErr)
		return
	}

	publicationStatus := activityPublicationStatus(requestedStatus)
	now := time.Now().UTC()
	responseStatus := activityStatusForResponse(publicationStatus, input.StartAt, input.EndAt, now)
	phase := activityPhaseForPublication(publicationStatus, input.StartAt, input.EndAt, now)
	var publishedAt *time.Time
	if publicationStatus == "published" {
		publishedAt = &now
	}

	activityID := newPostID()
	coverMediaID := strings.TrimSpace(input.CoverMediaID)
	coverURL := strings.TrimSpace(input.CoverURL)

	_, err := s.db.ExecContext(r.Context(), `
		INSERT INTO activities (
			id, title, description, cover_media_id, cover_url,
			start_at, end_at, location, status, publication_status, created_by, published_at, created_at, updated_at
		) VALUES (
			$1, $2, $3, NULLIF($4, ''), $5,
			$6, $7, $8, $9, $10, $11, $12, $12, $12
		)`,
		activityID, title, strings.TrimSpace(input.Description), coverMediaID, coverURL,
		input.StartAt, input.EndAt, strings.TrimSpace(input.Location), responseStatus, publicationStatus, user.ID, publishedAt, now,
	)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	httpserver.WriteJSON(w, http.StatusCreated, map[string]any{
		"id":                 activityID,
		"status":             responseStatus,
		"publication_status": publicationStatus,
		"phase":              phase,
		"message":            "活动已创建",
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

	if timeErr := validateActivityTimes(input.StartAt, input.EndAt); timeErr != nil {
		httpserver.WriteAppError(w, r, *timeErr)
		return
	}

	requestedStatus, statusErr := validateActivityStatus(input.Status)
	if statusErr != nil {
		httpserver.WriteAppError(w, r, *statusErr)
		return
	}

	publicationStatus := activityPublicationStatus(requestedStatus)
	now := time.Now().UTC()
	responseStatus := activityStatusForResponse(publicationStatus, input.StartAt, input.EndAt, now)
	phase := activityPhaseForPublication(publicationStatus, input.StartAt, input.EndAt, now)
	coverMediaID := strings.TrimSpace(input.CoverMediaID)
	coverURL := strings.TrimSpace(input.CoverURL)

	res, err := s.db.ExecContext(r.Context(), `
		UPDATE activities
		SET title = $1, description = $2, cover_media_id = NULLIF($3, ''), cover_url = $4,
		    start_at = $5, end_at = $6, location = $7, status = $8,
		    publication_status = $9,
		    published_at = CASE WHEN $9 = 'published' THEN COALESCE(published_at, $10) ELSE published_at END,
		    updated_at = $10
		WHERE id = $11 AND deleted_at IS NULL`,
		title, strings.TrimSpace(input.Description), coverMediaID, coverURL,
		input.StartAt, input.EndAt, strings.TrimSpace(input.Location), responseStatus, publicationStatus, now, activityID,
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

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": activityID, "status": responseStatus, "publication_status": publicationStatus, "phase": phase, "message": "活动已更新"})
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

	var startAt, endAt sql.NullTime
	err := s.db.QueryRowContext(r.Context(), `SELECT start_at, end_at FROM activities WHERE id = $1 AND deleted_at IS NULL`, activityID).Scan(&startAt, &endAt)
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

	now := time.Now().UTC()
	if endAt.Valid && !now.Before(endAt.Time) {
		httpserver.WriteAppError(w, r, httpserver.AppError{
			Status:  http.StatusConflict,
			Code:    "ACTIVITY_ALREADY_ENDED",
			Message: "已结束的活动不能发布",
		})
		return
	}

	newStatus := deriveActivityPhase(nullableTime(startAt), nullableTime(endAt), now)

	_, err = s.db.ExecContext(r.Context(), `
		UPDATE activities
		SET status = $1, publication_status = 'published', published_at = COALESCE(published_at, now()), updated_at = now()
		WHERE id = $2 AND deleted_at IS NULL`, newStatus, activityID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": activityID, "status": newStatus, "publication_status": "published", "phase": newStatus, "message": "活动已发布"})
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
		SET status = 'offline', publication_status = 'offline', updated_at = now()
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

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": activityID, "status": "offline", "publication_status": "offline", "phase": "", "message": "活动已下架"})
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
		       a.start_at, a.end_at, a.location, a.publication_status, a.created_by,
		       COALESCE(up.nickname, u.username, ''), a.published_at, a.created_at, a.updated_at
		FROM activities a
		JOIN users u ON u.id = a.created_by
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets ma ON ma.id = a.cover_media_id AND ma.deleted_at IS NULL
		WHERE a.deleted_at IS NULL AND a.publication_status = 'published'
		ORDER BY COALESCE(a.start_at, a.published_at, a.created_at) DESC
		LIMIT 50`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()

	now := time.Now().UTC()
	items := make([]activityResponse, 0)
	for rows.Next() {
		var item activityResponse
		var coverMediaID, coverKey string
		var startAt, endAt, publishedAt sql.NullTime
		if err := rows.Scan(
			&item.ID, &item.Title, &item.Description, &coverMediaID,
			&coverKey, &startAt, &endAt, &item.Location, &item.PublicationStatus,
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
		hydrateActivityStatus(&item, now)
		items = append(items, item)
	}

	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}
