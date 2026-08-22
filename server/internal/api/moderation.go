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

var (
	ErrPermissionDenied        = errors.New("permission denied")
	ErrInvalidModerationAction = errors.New("invalid moderation action")
	ErrModerationCaseNotFound  = errors.New("moderation case not found")
)

type moderationActionInput struct {
	Action string `json:"action"`
	Reason string `json:"reason"`
}

func (s *Server) createModerationAction(w http.ResponseWriter, r *http.Request, caseID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.hasPermission(r, user.ID, "moderation.action") {
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
	if err := applyModerationAction(r, tx, user.ID, caseID, targetType, targetID, input); err != nil {
		writeAuthError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO moderation_actions (id, case_id, operator_id, action, reason, created_at) VALUES ($1, $2, $3, $4, $5, $6)`, newPostID(), caseID, user.ID, input.Action, strings.TrimSpace(input.Reason), time.Now().UTC()); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if _, err := tx.ExecContext(r.Context(), `UPDATE moderation_cases SET status = 'resolved', resolved_at = now() WHERE id = $1`, caseID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"case_id": caseID, "action": input.Action, "status": "resolved"})
}

func (s *Server) hasPermission(r *http.Request, userID, permission string) bool {
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

func applyModerationAction(r *http.Request, tx *sql.Tx, operatorID, caseID, targetType, targetID string, input moderationActionInput) error {
	before := map[string]any{"target_type": targetType, "target_id": targetID}
	var query string
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
			query = `UPDATE comments SET publication_status = 'deleted', deleted_at = COALESCE(deleted_at, now()), deleted_by = $1, delete_reason = $2, moderation_case_id = $3, updated_at = now() WHERE id = $4`
		}
	default:
		return ErrInvalidModerationAction
	}
	if query == "" {
		return ErrInvalidModerationAction
	}
	var args []any
	switch input.Action {
	case "hide":
		args = []any{caseID, strings.TrimSpace(input.Reason), targetID}
	case "restore":
		args = []any{targetID}
	case "delete":
		args = []any{operatorID, strings.TrimSpace(input.Reason), caseID, targetID}
	}
	result, err := tx.ExecContext(r.Context(), query, args...)
	if err != nil {
		return err
	}
	rows, err := result.RowsAffected()
	if err != nil || rows != 1 {
		return ErrModerationCaseNotFound
	}
	after := map[string]any{"action": input.Action, "reason": strings.TrimSpace(input.Reason)}
	beforeJSON, _ := json.Marshal(before)
	afterJSON, _ := json.Marshal(after)
	_, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs (id, operator_id, action, target_type, target_id, reason, before_data, after_data, request_id, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9, $10)`, newPostID(), operatorID, "moderation."+input.Action, targetType, targetID, strings.TrimSpace(input.Reason), beforeJSON, afterJSON, r.Header.Get("X-Request-ID"), time.Now().UTC())
	return err
}

func validModerationAction(input moderationActionInput) bool {
	if strings.TrimSpace(input.Reason) == "" || len([]rune(input.Reason)) > 1000 {
		return false
	}
	switch input.Action {
	case "hide", "restore", "delete":
		return true
	default:
		return false
	}
}
