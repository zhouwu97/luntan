package api

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrPermissionDenied        = errors.New("permission denied")
	ErrSuperAdminRequired      = errors.New("super admin required")
	ErrInvalidModerationAction = errors.New("invalid moderation action")
	ErrModerationCaseNotFound  = errors.New("moderation case not found")
	ErrTargetRoleProtected     = errors.New("moderation target role is protected")
)

const (
	roleRankUser               = 0
	roleRankCommunityModerator = 1
	roleRankCommunityOwner     = 2
	roleRankPlatformModerator  = 3
	roleRankPlatformAdmin      = 4
	roleRankSuperAdmin         = 5
)

var moderationRoleRanks = map[string]int{
	"user":                roleRankUser,
	"community_moderator": roleRankCommunityModerator,
	"community_owner":     roleRankCommunityOwner,
	"platform_moderator":  roleRankPlatformModerator,
	"platform_admin":      roleRankPlatformAdmin,
	"super_admin":         roleRankSuperAdmin,
}

type moderationActionInput struct {
	Action       string `json:"action"`
	Reason       string `json:"reason"`
	DurationDays int    `json:"duration_days"`
	Permanent    bool   `json:"permanent"`
}

type moderationCursor struct {
	CreatedAt time.Time `json:"created_at"`
	ID        string    `json:"id"`
}

func (s *Server) createModerationAction(w http.ResponseWriter, r *http.Request, caseID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasPermission(r, user.ID, caseID, "moderation.action") {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	var input moderationActionInput
	if err := decodeJSON(r, &input); err != nil || !validModerationAction(input) {
		writeAuthError(w, r, ErrInvalidModerationAction)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var targetType, targetID, status string
	err = tx.QueryRowContext(r.Context(), `SELECT target_type, target_id, status FROM moderation_cases WHERE id = $1 FOR UPDATE`, caseID).Scan(&targetType, &targetID, &status)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrModerationCaseNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var ownerID, targetTitle, targetContent string
	switch targetType {
	case "post":
		err = tx.QueryRowContext(r.Context(), `SELECT author_id, title, content FROM posts WHERE id = $1`, targetID).Scan(&ownerID, &targetTitle, &targetContent)
	case "comment":
		err = tx.QueryRowContext(r.Context(), `SELECT author_id, '评论', content FROM comments WHERE id = $1`, targetID).Scan(&ownerID, &targetTitle, &targetContent)
	case "user":
		err = tx.QueryRowContext(r.Context(), `SELECT id, '账号处理', username FROM users WHERE id = $1 AND deleted_at IS NULL`, targetID).Scan(&ownerID, &targetTitle, &targetContent)
	default:
		err = ErrInvalidModerationAction
	}
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrModerationCaseNotFound)
		return
	}
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	if err := applyModerationAction(r, tx, user.ID, caseID, targetType, targetID, input); err != nil {
		writeAuthError(w, r, err)
		return
	}
	actionID := newPostID()
	now := time.Now().UTC()
	appealable := input.Action == "hide" || input.Action == "delete" || input.Action == "mute" || input.Action == "ban"
	durationDays := input.DurationDays
	if durationDays == 0 && input.Action == "mute" && !input.Permanent {
		durationDays = 7
	}
	var endsAt any
	if durationDays > 0 {
		endsAt = now.Add(time.Duration(durationDays) * 24 * time.Hour)
	}
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO moderation_actions (id, case_id, operator_id, action, reason, appealable, duration_days, starts_at, ends_at, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $8)`, actionID, caseID, user.ID, input.Action, strings.TrimSpace(input.Reason), appealable, durationDays, now, endsAt); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `UPDATE moderation_cases SET status = 'resolved', resolved_at = now() WHERE id = $1`, caseID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `UPDATE reports SET status = 'resolved', resolved_at = now() WHERE target_type = $1 AND target_id = $2 AND status IN ('pending', 'reviewing')`, targetType, targetID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if appealable {
		if err := enqueueNotificationWithDataTx(tx, ownerID, user.ID, "moderation.action", "moderation_action", actionID, map[string]any{
			"moderation_action_id": actionID,
			"target_type":          targetType,
			"target_id":            targetID,
			"action":               input.Action,
			"reason":               strings.TrimSpace(input.Reason),
			"target_title":         targetTitle,
			"target_content":       targetContent,
			"appealable":           true,
		}, now); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"case_id": caseID, "action_id": actionID, "action": input.Action, "status": "resolved"})
}

func (s *Server) hasPermission(r *http.Request, userID, caseID, permission string) bool {
	var targetType, targetID string
	if err := s.db.QueryRowContext(r.Context(), `SELECT target_type, target_id FROM moderation_cases WHERE id = $1`, caseID).Scan(&targetType, &targetID); err != nil {
		return false
	}
	communityID := ""
	switch targetType {
	case "post":
		if err := s.db.QueryRowContext(r.Context(), `SELECT community_id FROM posts WHERE id = $1`, targetID).Scan(&communityID); err != nil {
			return false
		}
	case "comment":
		if err := s.db.QueryRowContext(r.Context(), `SELECT p.community_id FROM comments c JOIN posts p ON p.id = c.post_id WHERE c.id = $1`, targetID).Scan(&communityID); err != nil {
			return false
		}
	}
	return s.hasScopedPermission(r, userID, permission, communityID)
}

func (s *Server) hasScopedPermission(r *http.Request, userID, permission, communityID string) bool {
	return hasScopedPermissionQuery(r.Context(), s.db, userID, permission, communityID)
}

func hasScopedPermissionQuery(ctx context.Context, queryer queryRowContext, userID, permission, communityID string) bool {
	var allowed bool
	err := queryer.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM user_roles ur
			JOIN role_permissions rp ON rp.role_id = ur.role_id
			JOIN permissions p ON p.id = rp.permission_id
			WHERE ur.user_id = $1 AND p.name = $2
			  AND (ur.community_id IS NULL OR ur.community_id = NULLIF($3, ''))
		)`, userID, permission, communityID).Scan(&allowed)
	return err == nil && allowed
}

func (s *Server) hasAnyPermission(r *http.Request, userID, permission string) bool {
	var allowed bool
	err := s.db.QueryRowContext(r.Context(), `
		SELECT EXISTS (
			SELECT 1 FROM user_roles ur
			JOIN role_permissions rp ON rp.role_id = ur.role_id
			JOIN permissions p ON p.id = rp.permission_id
			WHERE ur.user_id = $1 AND p.name = $2
		)`, userID, permission).Scan(&allowed)
	return err == nil && allowed
}

// hasGlobalPermission 只接受未绑定社区的角色权限，用于平台级管理接口。
// 社区角色即使拥有同名能力，也必须经过带 community_id 的作用域校验，不能借此访问全局资源。
func (s *Server) hasGlobalPermission(r *http.Request, userID, permission string) bool {
	var allowed bool
	err := s.db.QueryRowContext(r.Context(), `
		SELECT EXISTS (
			SELECT 1 FROM user_roles ur
			JOIN role_permissions rp ON rp.role_id = ur.role_id
			JOIN permissions p ON p.id = rp.permission_id
			WHERE ur.user_id = $1 AND p.name = $2 AND ur.community_id IS NULL
		)`, userID, permission).Scan(&allowed)
	return err == nil && allowed
}

// hasGlobalRole 只认未绑定社区的角色，供“恢复未打码原图”等不可逆风险更高的
// 平台级操作使用。前端 capability 仅用于隐藏按钮，最终权限仍由这里查询数据库。
func (s *Server) hasGlobalRole(r *http.Request, userID, role string) bool {
	return hasGlobalRoleQuery(r.Context(), s.db, userID, role)
}

func hasGlobalRoleQuery(ctx context.Context, queryer queryRowContext, userID, role string) bool {
	var allowed bool
	err := queryer.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM user_roles ur
			JOIN roles rl ON rl.id = ur.role_id
			WHERE ur.user_id = $1 AND rl.name = $2 AND ur.community_id IS NULL
		)`, userID, role).Scan(&allowed)
	return err == nil && allowed
}

func (s *Server) listModerationCases(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasAnyPermission(r, user.ID, "report.review") {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 无效"})
		return
	}
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	var cursor *moderationCursor
	if raw := strings.TrimSpace(r.URL.Query().Get("cursor")); raw != "" {
		decoded, decodeErr := decodeModerationCursor(raw)
		if decodeErr != nil {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		cursor = &decoded
	}
	communityExpression := `COALESCE(p.community_id, cp.community_id, '')`
	args := []any{status, user.ID}
	query := `
		SELECT mc.id, mc.target_type, mc.target_id, mc.source, mc.risk_level, mc.status, mc.created_at, mc.resolved_at,
		       ` + communityExpression + ` AS community_id
		FROM moderation_cases mc
		LEFT JOIN posts p ON mc.target_type = 'post' AND p.id = mc.target_id
		LEFT JOIN comments c ON mc.target_type = 'comment' AND c.id = mc.target_id
		LEFT JOIN posts cp ON c.post_id = cp.id
		WHERE ($1 = '' OR mc.status = $1)
		  AND EXISTS (
			SELECT 1
			FROM user_roles ur
			JOIN role_permissions rp ON rp.role_id = ur.role_id
			JOIN permissions pmt ON pmt.id = rp.permission_id
			WHERE ur.user_id = $2 AND pmt.name = 'report.review'
			  AND (ur.community_id IS NULL OR ur.community_id = ` + communityExpression + `)
		  )`
	if cursor != nil {
		query += " AND (mc.created_at, mc.id) > ($3, $4)"
		args = append(args, cursor.CreatedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	query += " ORDER BY mc.created_at ASC, mc.id ASC LIMIT $" + strconv.Itoa(limitPosition)
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	lastCreatedAt := time.Time{}
	lastID := ""
	for rows.Next() {
		var id, targetType, targetID, source, riskLevel, caseStatus, communityID string
		var createdAt time.Time
		var resolvedAt sql.NullTime
		if err := rows.Scan(&id, &targetType, &targetID, &source, &riskLevel, &caseStatus, &createdAt, &resolvedAt, &communityID); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item := map[string]any{"id": id, "target_type": targetType, "target_id": targetID, "source": source, "risk_level": riskLevel, "status": caseStatus, "community_id": communityID, "created_at": createdAt}
		if resolvedAt.Valid {
			item["resolved_at"] = resolvedAt.Time
		}
		items = append(items, item)
		lastCreatedAt, lastID = createdAt, id
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
		last := items[len(items)-1]
		lastCreatedAt = last["created_at"].(time.Time)
		lastID = last["id"].(string)
	}
	var nextCursor any
	if hasMore {
		encoded, encodeErr := encodeModerationCursor(moderationCursor{CreatedAt: lastCreatedAt, ID: lastID})
		if encodeErr != nil {
			writeInternalError(w, r, encodeErr)
			return
		}
		nextCursor = encoded
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": nextCursor, "has_more": hasMore})
}

func encodeModerationCursor(cursor moderationCursor) (string, error) {
	data, err := json.Marshal(cursor)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

// getModerationCase 返回审核员做决定所需的案件上下文，避免只显示 target_id
// 就直接执行隐藏、删除或处罚。
func (s *Server) getModerationCase(w http.ResponseWriter, r *http.Request, caseID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var targetType, targetID, source, riskLevel, status, communityID string
	var createdAt time.Time
	var resolvedAt sql.NullTime
	err := s.db.QueryRowContext(r.Context(), `
		SELECT mc.target_type, mc.target_id, mc.source, mc.risk_level, mc.status,
		       mc.created_at, mc.resolved_at,
		       COALESCE(p.community_id, cp.community_id, '')
		FROM moderation_cases mc
		LEFT JOIN posts p ON mc.target_type = 'post' AND p.id = mc.target_id
		LEFT JOIN comments c ON mc.target_type = 'comment' AND c.id = mc.target_id
		LEFT JOIN posts cp ON c.post_id = cp.id
		WHERE mc.id = $1`, caseID).Scan(&targetType, &targetID, &source, &riskLevel, &status, &createdAt, &resolvedAt, &communityID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrModerationCaseNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if !s.hasScopedPermission(r, user.ID, "report.review", communityID) {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	}

	target := map[string]any{"type": targetType, "id": targetID}
	var authorID, authorName, title, content string
	var targetCreatedAt time.Time
	switch targetType {
	case "post":
		err = s.db.QueryRowContext(r.Context(), `
			SELECT p.author_id, COALESCE(up.nickname, u.username), p.title, p.content, p.created_at
			FROM posts p JOIN users u ON u.id = p.author_id
			LEFT JOIN user_profiles up ON up.user_id = p.author_id WHERE p.id = $1`, targetID).
			Scan(&authorID, &authorName, &title, &content, &targetCreatedAt)
		if err == nil {
			mediaRows, mediaErr := s.db.QueryContext(r.Context(), `SELECT media_id FROM post_media WHERE post_id = $1 ORDER BY sort_order, media_id`, targetID)
			if mediaErr != nil {
				writeInternalError(w, r, mediaErr)
				return
			}
			mediaIDs := make([]string, 0)
			for mediaRows.Next() {
				var mediaID string
				if scanErr := mediaRows.Scan(&mediaID); scanErr != nil {
					mediaRows.Close()
					writeInternalError(w, r, scanErr)
					return
				}
				mediaIDs = append(mediaIDs, mediaID)
			}
			if rowsErr := mediaRows.Err(); rowsErr != nil {
				mediaRows.Close()
				writeInternalError(w, r, rowsErr)
				return
			}
			mediaRows.Close()
			target["media_ids"] = mediaIDs
		}
	case "comment":
		err = s.db.QueryRowContext(r.Context(), `
			SELECT c.author_id, COALESCE(up.nickname, u.username), '评论', c.content, c.created_at
			FROM comments c JOIN users u ON u.id = c.author_id
			LEFT JOIN user_profiles up ON up.user_id = c.author_id WHERE c.id = $1`, targetID).
			Scan(&authorID, &authorName, &title, &content, &targetCreatedAt)
	case "user":
		err = s.db.QueryRowContext(r.Context(), `
			SELECT u.id, COALESCE(up.nickname, u.username), '账号处理', u.username, u.created_at
			FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id
			WHERE u.id = $1`, targetID).
			Scan(&authorID, &authorName, &title, &content, &targetCreatedAt)
	default:
		writeAuthError(w, r, ErrInvalidModerationAction)
		return
	}
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrModerationCaseNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	target["author_id"] = authorID
	target["author_name"] = authorName
	target["title"] = title
	target["content"] = content
	target["created_at"] = targetCreatedAt

	var reportCount int64
	var reportReasons string
	var firstReportedAt, lastReportedAt sql.NullTime
	if err := s.db.QueryRowContext(r.Context(), `
		SELECT count(*), COALESCE(string_agg(DISTINCT reason_code, ', ' ORDER BY reason_code), ''), min(created_at), max(created_at)
		FROM reports WHERE target_type = $1 AND target_id = $2`, targetType, targetID).
		Scan(&reportCount, &reportReasons, &firstReportedAt, &lastReportedAt); err != nil {
		writeInternalError(w, r, err)
		return
	}
	report := map[string]any{"count": reportCount, "reasons": reportReasons}
	if firstReportedAt.Valid {
		report["first_at"] = firstReportedAt.Time
	}
	if lastReportedAt.Valid {
		report["last_at"] = lastReportedAt.Time
	}

	account := map[string]any{}
	if authorID != "" {
		var accountCreatedAt time.Time
		var accountStatus string
		var priorReports, priorActions int64
		if err := s.db.QueryRowContext(r.Context(), `
			SELECT u.created_at, u.status,
			       (SELECT count(*) FROM reports WHERE reporter_id = u.id),
			       (SELECT count(*) FROM moderation_actions ma JOIN moderation_cases mc ON mc.id = ma.case_id WHERE mc.target_type = 'user' AND mc.target_id = u.id)
			FROM users u WHERE u.id = $1`, authorID).
			Scan(&accountCreatedAt, &accountStatus, &priorReports, &priorActions); err != nil {
			writeInternalError(w, r, err)
			return
		}
		account = map[string]any{"user_id": authorID, "created_at": accountCreatedAt, "status": accountStatus, "report_count": priorReports, "punishment_count": priorActions}
	}
	result := map[string]any{
		"id": caseID, "target_type": targetType, "target_id": targetID,
		"source": source, "risk_level": riskLevel, "status": status,
		"community_id": communityID, "created_at": createdAt,
		"target": target, "report": report, "account": account,
	}
	if resolvedAt.Valid {
		result["resolved_at"] = resolvedAt.Time
	}
	httpserver.WriteJSON(w, http.StatusOK, result)
}

func decodeModerationCursor(value string) (moderationCursor, error) {
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return moderationCursor{}, err
	}
	var cursor moderationCursor
	if err := json.Unmarshal(data, &cursor); err != nil || cursor.ID == "" || cursor.CreatedAt.IsZero() {
		return moderationCursor{}, errors.New("invalid moderation cursor")
	}
	return cursor, nil
}

func applyModerationAction(r *http.Request, tx *sql.Tx, operatorID, caseID, targetType, targetID string, input moderationActionInput) error {
	before := map[string]any{"target_type": targetType, "target_id": targetID}
	var query string
	var affected int64
	if targetType == "user" {
		if err := authorizeManagedTargetTx(r.Context(), tx, operatorID, targetID); err != nil {
			return err
		}
	}
	switch targetType {
	case "post":
		switch input.Action {
		case "hide":
			query = `UPDATE posts SET post_status = 'hidden', moderation_status = 'hidden', moderation_case_id = $1, visibility_reason = $2, updated_at = now() WHERE id = $3`
		case "restore":
			query = `UPDATE posts SET post_status = 'published', moderation_status = 'normal', moderation_case_id = NULL, visibility_reason = '', updated_at = now() WHERE id = $1`
		case "delete":
			query = `UPDATE posts SET post_status = 'deleted', publication_status = 'deleted', deleted_at = COALESCE(deleted_at, now()), deleted_by = $1, delete_reason = $2, moderation_case_id = $3, updated_at = now() WHERE id = $4`
		}
	case "comment":
		switch input.Action {
		case "hide":
			query = `UPDATE comments SET moderation_status = 'hidden', moderation_case_id = $1, visibility_reason = $2, updated_at = now() WHERE id = $3`
		case "restore":
			query = `UPDATE comments SET moderation_status = 'normal', moderation_case_id = NULL, visibility_reason = '', updated_at = now() WHERE id = $1`
		case "delete":
			changed, err := softDeleteCommentTx(r.Context(), tx, targetID, operatorID, input.Reason, caseID)
			if err != nil {
				return err
			}
			if !changed {
				return ErrModerationCaseNotFound
			}
			affected = 1
		}
	case "user":
		if input.Action != "mute" && input.Action != "ban" && input.Action != "restore" {
			return ErrInvalidModerationAction
		}
		query = `UPDATE users SET status = CASE WHEN $1 = 'ban' THEN 'suspended' WHEN $1 = 'restore' THEN 'active' ELSE status END, updated_at = now() WHERE id = $2 AND deleted_at IS NULL`
	default:
		return ErrInvalidModerationAction
	}
	if query == "" && affected != 1 {
		return ErrInvalidModerationAction
	}
	var args []any
	if targetType == "user" {
		args = []any{input.Action, targetID}
	} else {
		switch input.Action {
		case "hide":
			args = []any{caseID, strings.TrimSpace(input.Reason), targetID}
		case "restore":
			args = []any{targetID}
		case "delete":
			if targetType == "comment" {
				break
			}
			args = []any{operatorID, strings.TrimSpace(input.Reason), caseID, targetID}
		case "mute", "ban":
			args = []any{targetID}
		}
	}
	if query != "" {
		result, err := tx.ExecContext(r.Context(), query, args...)
		if err != nil {
			return err
		}
		affected, err = result.RowsAffected()
		if err != nil {
			return err
		}
	}
	if targetType == "user" {
		durationDays := input.DurationDays
		if durationDays == 0 && input.Action == "mute" && !input.Permanent {
			durationDays = 7
		}
		var endsAt any
		if durationDays > 0 {
			endsAt = time.Now().UTC().Add(time.Duration(durationDays) * 24 * time.Hour)
		}
		switch input.Action {
		case "mute":
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO restrictions (id, user_id, restriction_type, limit_value, window_seconds, reason, starts_at, ends_at, operator_id) VALUES ($1, $2, 'mute', 0, 0, $3, now(), $4, $5)`, newPostID(), targetID, strings.TrimSpace(input.Reason), endsAt, operatorID); err != nil {
				return err
			}
		case "ban":
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO bans (id, user_id, operator_id, scope, reason, starts_at, ends_at) VALUES ($1, $2, $3, 'platform', $4, now(), $5)`, newPostID(), targetID, operatorID, strings.TrimSpace(input.Reason), endsAt); err != nil {
				return err
			}
		case "restore":
			if _, err := tx.ExecContext(r.Context(), `UPDATE bans SET revoked_at = COALESCE(revoked_at, now()) WHERE user_id = $1 AND revoked_at IS NULL`, targetID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE restrictions SET ends_at = COALESCE(ends_at, now()) WHERE user_id = $1 AND restriction_type = 'mute' AND (ends_at IS NULL OR ends_at > now())`, targetID); err != nil {
				return err
			}
		}
	}
	if affected != 1 {
		return ErrModerationCaseNotFound
	}
	after := map[string]any{"action": input.Action, "reason": strings.TrimSpace(input.Reason)}
	beforeJSON, _ := json.Marshal(before)
	afterJSON, _ := json.Marshal(after)
	var err error
	_, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs (id, operator_id, action, target_type, target_id, reason, before_data, after_data, request_id, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9, $10)`, newPostID(), operatorID, "moderation."+input.Action, targetType, targetID, strings.TrimSpace(input.Reason), beforeJSON, afterJSON, r.Header.Get("X-Request-ID"), time.Now().UTC())
	if err != nil {
		return err
	}
	return appendAdminLogTx(r.Context(), tx, operatorID, "moderation."+input.Action, targetType, targetID, strings.TrimSpace(input.Reason), r.Header.Get("X-Request-ID"), httpserver.ClientIP(r), after, time.Now().UTC())
}

// authorizeManagedTargetTx 在实际处罚写入前锁定目标账号并比较双方最高角色。
// 该检查必须位于事务内，避免仅依赖 Handler 层的权限判断而被其他治理入口绕过。
func authorizeManagedTargetTx(ctx context.Context, tx *sql.Tx, operatorID, targetID string) error {
	if strings.TrimSpace(operatorID) == "" || strings.TrimSpace(targetID) == "" || operatorID == targetID {
		return ErrTargetRoleProtected
	}
	var lockedTargetID string
	if err := tx.QueryRowContext(ctx, `SELECT id FROM users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`, targetID).Scan(&lockedTargetID); errors.Is(err, sql.ErrNoRows) {
		return ErrModerationCaseNotFound
	} else if err != nil {
		return err
	}

	rows, err := tx.QueryContext(ctx, `
		SELECT ur.user_id, rl.name
		FROM user_roles ur
		JOIN roles rl ON rl.id = ur.role_id
		WHERE ur.user_id IN ($1, $2)
		ORDER BY ur.user_id, rl.name
		FOR UPDATE OF ur`, operatorID, targetID)
	if err != nil {
		return err
	}
	defer rows.Close()
	ranks := map[string]int{operatorID: roleRankUser, targetID: roleRankUser}
	for rows.Next() {
		var userID, roleName string
		if err := rows.Scan(&userID, &roleName); err != nil {
			return err
		}
		rank, known := moderationRoleRanks[roleName]
		if !known {
			// 未知角色不能被当成普通用户处理，避免新增高权限角色时绕过
			// 目标保护；角色映射补齐后才允许继续治理。
			return ErrTargetRoleProtected
		}
		if rank > ranks[userID] {
			ranks[userID] = rank
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if ranks[operatorID] <= ranks[targetID] {
		return ErrTargetRoleProtected
	}
	return nil
}

func validModerationAction(input moderationActionInput) bool {
	if strings.TrimSpace(input.Reason) == "" || len([]rune(input.Reason)) > 1000 || input.DurationDays < 0 || input.DurationDays > 365 {
		return false
	}
	switch input.Action {
	case "hide", "restore", "delete", "mute", "ban":
		return true
	default:
		return false
	}
}
