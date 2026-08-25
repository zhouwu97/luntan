package api

import (
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
	ErrInvalidModerationAction = errors.New("invalid moderation action")
	ErrModerationCaseNotFound  = errors.New("moderation case not found")
)

type moderationActionInput struct {
	Action string `json:"action"`
	Reason string `json:"reason"`
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
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO moderation_actions (id, case_id, operator_id, action, reason, appealable, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7)`, actionID, caseID, user.ID, input.Action, strings.TrimSpace(input.Reason), appealable, now); err != nil {
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
	var allowed bool
	err := s.db.QueryRowContext(r.Context(), `
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
	switch targetType {
	case "post":
		switch input.Action {
		case "hide":
			query = `UPDATE posts SET moderation_status = 'hidden', moderation_case_id = $1, visibility_reason = $2, updated_at = now() WHERE id = $3`
		case "restore":
			query = `UPDATE posts SET moderation_status = 'normal', moderation_case_id = NULL, visibility_reason = '', updated_at = now() WHERE id = $1`
		case "delete":
			query = `UPDATE posts SET publication_status = 'deleted', deleted_at = COALESCE(deleted_at, now()), deleted_by = $1, delete_reason = $2, moderation_case_id = $3, updated_at = now() WHERE id = $4`
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
		query = `UPDATE users SET status = CASE WHEN $1 = 'restore' THEN 'active' ELSE 'suspended' END, updated_at = now() WHERE id = $2 AND deleted_at IS NULL`
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
	if affected != 1 {
		return ErrModerationCaseNotFound
	}
	after := map[string]any{"action": input.Action, "reason": strings.TrimSpace(input.Reason)}
	beforeJSON, _ := json.Marshal(before)
	afterJSON, _ := json.Marshal(after)
	var err error
	_, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs (id, operator_id, action, target_type, target_id, reason, before_data, after_data, request_id, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9, $10)`, newPostID(), operatorID, "moderation."+input.Action, targetType, targetID, strings.TrimSpace(input.Reason), beforeJSON, afterJSON, r.Header.Get("X-Request-ID"), time.Now().UTC())
	return err
}

func validModerationAction(input moderationActionInput) bool {
	if strings.TrimSpace(input.Reason) == "" || len([]rune(input.Reason)) > 1000 {
		return false
	}
	switch input.Action {
	case "hide", "restore", "delete", "mute", "ban":
		return true
	default:
		return false
	}
}
