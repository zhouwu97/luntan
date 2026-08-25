package api

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

func (s *Server) accountStatus(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	var email, accountType, status string
	var verified bool
	var verifiedAt sql.NullTime
	var createdAt time.Time
	if err := s.db.QueryRowContext(r.Context(), `SELECT COALESCE(email, ''), COALESCE(account_type, 'email'), status, email_verified, email_verified_at, created_at FROM users WHERE id = $1 AND deleted_at IS NULL`, user.ID).Scan(&email, &accountType, &status, &verified, &verifiedAt, &createdAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeAuthError(w, r, ErrPermissionDenied)
		} else {
			writeInternalError(w, r, err)
		}
		return
	}
	type punishment struct {
		ID         string     `json:"id"`
		Type       string     `json:"type"`
		Action     string     `json:"action,omitempty"`
		Reason     string     `json:"reason"`
		StartsAt   time.Time  `json:"starts_at"`
		EndsAt     *time.Time `json:"ends_at,omitempty"`
		CreatedAt  time.Time  `json:"created_at"`
		Appealable bool       `json:"appealable,omitempty"`
	}
	items := make([]punishment, 0, 8)
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT b.id, 'ban', '', b.reason, b.starts_at, b.ends_at, b.created_at, false
		FROM bans b WHERE b.user_id = $1 AND b.revoked_at IS NULL
		UNION ALL
		SELECT r.id, r.restriction_type, '', r.reason, r.starts_at, r.ends_at, r.created_at, false
		FROM restrictions r WHERE r.user_id = $1
		UNION ALL
		SELECT ma.id, 'moderation', ma.action, ma.reason, ma.starts_at, ma.ends_at, ma.created_at, ma.appealable
		FROM moderation_actions ma JOIN moderation_cases mc ON mc.id = ma.case_id
		WHERE mc.target_type = 'user' AND mc.target_id = $1
		ORDER BY created_at DESC`, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		var item punishment
		var endsAt sql.NullTime
		if err := rows.Scan(&item.ID, &item.Type, &item.Action, &item.Reason, &item.StartsAt, &endsAt, &item.CreatedAt, &item.Appealable); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if endsAt.Valid {
			item.EndsAt = &endsAt.Time
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	result := map[string]any{"user_id": user.ID, "username": user.Username, "status": status, "account_type": accountType, "email": email, "email_verified": verified, "created_at": createdAt, "punishments": items}
	if verifiedAt.Valid {
		result["email_verified_at"] = verifiedAt.Time
	}
	httpserver.WriteJSON(w, http.StatusOK, result)
}

func (s *Server) listAdmins(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok || !s.hasAnyPermission(r, user.ID, "audit.read") {
		if ok {
			writeAuthError(w, r, ErrPermissionDenied)
		}
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT u.id, u.username, COALESCE(up.nickname, u.username), COALESCE(u.email, ''), u.status,
		       string_agg(DISTINCT rl.name, ', ' ORDER BY rl.name), count(DISTINCT al.id), max(al.created_at)
		FROM users u JOIN user_roles ur ON ur.user_id = u.id JOIN roles rl ON rl.id = ur.role_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN audit_logs al ON al.operator_id = u.id
		WHERE rl.name IN ('community_moderator', 'community_owner', 'platform_moderator', 'platform_admin', 'super_admin')
		GROUP BY u.id, u.username, up.nickname, u.email, u.status
		ORDER BY u.username ASC`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, username, nickname, email, status, roles string
		var actionCount int64
		var lastAction sql.NullTime
		if err := rows.Scan(&id, &username, &nickname, &email, &status, &roles, &actionCount, &lastAction); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item := map[string]any{"id": id, "username": username, "nickname": nickname, "email": email, "status": status, "roles": strings.Split(roles, ", "), "action_count": actionCount}
		if lastAction.Valid {
			item["last_action_at"] = lastAction.Time
		}
		items = append(items, item)
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) getAdmin(w http.ResponseWriter, r *http.Request, adminID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok || !s.hasAnyPermission(r, user.ID, "audit.read") {
		if ok {
			writeAuthError(w, r, ErrPermissionDenied)
		}
		return
	}
	var username, nickname, email, status string
	if err := s.db.QueryRowContext(r.Context(), `SELECT u.username, COALESCE(up.nickname, u.username), COALESCE(u.email, ''), u.status FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id WHERE u.id = $1 AND u.deleted_at IS NULL`, adminID).Scan(&username, &nickname, &email, &status); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrPermissionDenied)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	rolesRows, err := s.db.QueryContext(r.Context(), `SELECT rl.name, COALESCE(ur.community_id, '') FROM user_roles ur JOIN roles rl ON rl.id = ur.role_id WHERE ur.user_id = $1 ORDER BY rl.name`, adminID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rolesRows.Close()
	roles := make([]map[string]string, 0)
	for rolesRows.Next() {
		var role, community string
		if err := rolesRows.Scan(&role, &community); err != nil {
			writeInternalError(w, r, err)
			return
		}
		roles = append(roles, map[string]string{"name": role, "community_id": community})
	}
	permissionRows, err := s.db.QueryContext(r.Context(), `SELECT DISTINCT p.name FROM user_roles ur JOIN role_permissions rp ON rp.role_id = ur.role_id JOIN permissions p ON p.id = rp.permission_id WHERE ur.user_id = $1 ORDER BY p.name`, adminID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer permissionRows.Close()
	permissions := make([]string, 0)
	for permissionRows.Next() {
		var permission string
		if err := permissionRows.Scan(&permission); err != nil {
			writeInternalError(w, r, err)
			return
		}
		permissions = append(permissions, permission)
	}
	actionRows, err := s.db.QueryContext(r.Context(), `SELECT id, action, target_type, target_id, reason, created_at FROM admin_logs WHERE operator_id = $1 ORDER BY created_at DESC, id DESC LIMIT 50`, adminID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer actionRows.Close()
	actions := make([]map[string]any, 0)
	for actionRows.Next() {
		var id, action, targetType, targetID, reason string
		var createdAt time.Time
		if err := actionRows.Scan(&id, &action, &targetType, &targetID, &reason, &createdAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		actions = append(actions, map[string]any{"id": id, "action": action, "target_type": targetType, "target_id": targetID, "reason": reason, "created_at": createdAt})
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": adminID, "username": username, "nickname": nickname, "email": email, "status": status, "roles": roles, "permissions": permissions, "recent_actions": actions})
}

func (s *Server) riskOverview(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok || !s.hasAnyPermission(r, user.ID, "audit.read") {
		if ok {
			writeAuthError(w, r, ErrPermissionDenied)
		}
		return
	}
	var codeRequests, abnormalIPs, automaticRestrictions int64
	if err := s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM risk_events WHERE event_type = 'email_code_requested' AND created_at >= date_trunc('day', now())`).Scan(&codeRequests); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM (SELECT ip_address FROM risk_events WHERE event_type = 'email_code_requested' AND created_at >= date_trunc('day', now()) AND ip_address <> '' GROUP BY ip_address HAVING count(*) >= 5) suspicious_ips`).Scan(&abnormalIPs); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM risk_events WHERE event_type = 'content_auto_review' AND created_at >= date_trunc('day', now())`).Scan(&automaticRestrictions); err != nil {
		writeInternalError(w, r, err)
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `SELECT id, event_type, severity, ip_address, metadata, created_at FROM risk_events ORDER BY created_at DESC LIMIT 30`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	events := make([]map[string]any, 0)
	for rows.Next() {
		var id, eventType, severity, ip string
		var metadata []byte
		var createdAt time.Time
		if err := rows.Scan(&id, &eventType, &severity, &ip, &metadata, &createdAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		events = append(events, map[string]any{"id": id, "event_type": eventType, "severity": severity, "ip_address": ip, "metadata": string(metadata), "created_at": createdAt})
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"code_requests": codeRequests, "abnormal_ips": abnormalIPs, "automatic_restrictions": automaticRestrictions, "events": events})
}

func (s *Server) adminLogs(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok || !s.hasAnyPermission(r, user.ID, "audit.read") {
		if ok {
			writeAuthError(w, r, ErrPermissionDenied)
		}
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `SELECT id, action, target_type, target_id, reason, previous_hash, hash, request_id, created_at FROM admin_logs ORDER BY created_at DESC, id DESC LIMIT 100`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, action, targetType, targetID, reason, previousHash, hash, requestID string
		var createdAt time.Time
		if err := rows.Scan(&id, &action, &targetType, &targetID, &reason, &previousHash, &hash, &requestID, &createdAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, map[string]any{"id": id, "action": action, "target_type": targetType, "target_id": targetID, "reason": reason, "previous_hash": previousHash, "hash": hash, "request_id": requestID, "created_at": createdAt})
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "chain": "sha256", "append_only": true})
}
