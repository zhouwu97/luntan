package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"net/netip"
	"sort"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
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
	queryText := strings.TrimSpace(r.URL.Query().Get("q"))
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT u.id, u.username, COALESCE(up.nickname, u.username), COALESCE(u.email, ''), u.status,
		       string_agg(DISTINCT rl.name, ', ' ORDER BY rl.name), count(DISTINCT al.id), max(al.created_at)
		FROM users u JOIN user_roles ur ON ur.user_id = u.id JOIN roles rl ON rl.id = ur.role_id
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN audit_logs al ON al.operator_id = u.id
		WHERE rl.name IN ('community_moderator', 'community_owner', 'platform_moderator', 'platform_admin', 'super_admin')
		  AND ($1 = '' OR u.username ILIKE '%' || $1 || '%' OR COALESCE(up.nickname, '') ILIKE '%' || $1 || '%')
		GROUP BY u.id, u.username, up.nickname, u.email, u.status
		ORDER BY u.username ASC`, queryText)
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
	rows, err := s.db.QueryContext(r.Context(), `SELECT id, action, target_type, target_id, reason, previous_hash, hash, request_id, ip_address, created_at FROM admin_logs ORDER BY created_at DESC, id DESC LIMIT 100`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, action, targetType, targetID, reason, previousHash, hash, requestID, ipAddress string
		var createdAt time.Time
		if err := rows.Scan(&id, &action, &targetType, &targetID, &reason, &previousHash, &hash, &requestID, &ipAddress, &createdAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, map[string]any{"id": id, "action": action, "target_type": targetType, "target_id": targetID, "reason": reason, "previous_hash": previousHash, "hash": hash, "request_id": requestID, "ip_address": ipAddress, "created_at": createdAt})
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items, "chain": "sha256", "append_only": true})
}

var (
	ErrInvalidAdminRole      = errors.New("invalid admin role assignment")
	ErrAdminRoleManageDenied = errors.New("admin role management denied")
	ErrLastSuperAdmin        = errors.New("cannot remove the last super admin")
	ErrInvalidIPRestriction  = errors.New("invalid ip restriction")
	ErrIPRestrictionNotFound = errors.New("ip restriction not found")
	adminRoleNames           = []string{"community_moderator", "community_owner", "platform_moderator", "platform_admin", "super_admin"}
)

type adminRoleAssignment struct {
	Name        string `json:"name"`
	CommunityID string `json:"community_id"`
}

type updateAdminRolesInput struct {
	Roles  []adminRoleAssignment `json:"roles"`
	Reason string                `json:"reason"`
}

func (s *Server) requireAdminRoleManager(w http.ResponseWriter, r *http.Request) (auth.User, bool) {
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return auth.User{}, false
	}
	if !s.hasAnyPermission(r, user.ID, "admin.role.manage") {
		writeAuthError(w, r, ErrAdminRoleManageDenied)
		return auth.User{}, false
	}
	var isSuperAdmin bool
	if err := s.db.QueryRowContext(r.Context(), `
		SELECT EXISTS (
			SELECT 1 FROM user_roles ur JOIN roles rl ON rl.id = ur.role_id
			WHERE ur.user_id = $1 AND rl.name = 'super_admin'
		)`, user.ID).Scan(&isSuperAdmin); err != nil || !isSuperAdmin {
		writeAuthError(w, r, ErrAdminRoleManageDenied)
		return auth.User{}, false
	}
	return user, true
}

func (s *Server) listAdminCandidates(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	if _, ok := s.requireAdminRoleManager(w, r); !ok {
		return
	}
	queryText := strings.TrimSpace(r.URL.Query().Get("q"))
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT u.id, u.username, COALESCE(up.nickname, u.username), COALESCE(u.email, '')
		FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE u.deleted_at IS NULL AND u.status = 'active'
		  AND ($1 = '' OR u.username ILIKE '%' || $1 || '%' OR COALESCE(up.nickname, '') ILIKE '%' || $1 || '%' OR COALESCE(u.email, '') ILIKE '%' || $1 || '%')
		ORDER BY u.username ASC LIMIT 50`, queryText)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, username, nickname, email string
		if err := rows.Scan(&id, &username, &nickname, &email); err != nil {
			writeInternalError(w, r, err)
			return
		}
		items = append(items, map[string]any{"id": id, "username": username, "nickname": nickname, "email": email})
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) updateAdminRoles(w http.ResponseWriter, r *http.Request, targetID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	operator, ok := s.requireAdminRoleManager(w, r)
	if !ok {
		return
	}
	if strings.TrimSpace(targetID) == "" || targetID == operator.ID {
		writeAuthError(w, r, ErrInvalidAdminRole)
		return
	}
	var input updateAdminRolesInput
	if err := decodeJSON(r, &input); err != nil || strings.TrimSpace(input.Reason) == "" || len([]rune(input.Reason)) > 1000 {
		writeAuthError(w, r, ErrInvalidAdminRole)
		return
	}
	if len(input.Roles) > len(adminRoleNames) {
		writeAuthError(w, r, ErrInvalidAdminRole)
		return
	}
	allowed := make(map[string]bool, len(adminRoleNames))
	for _, role := range adminRoleNames {
		allowed[role] = true
	}
	seen := map[string]bool{}
	for index := range input.Roles {
		role := &input.Roles[index]
		role.Name = strings.TrimSpace(role.Name)
		role.CommunityID = strings.TrimSpace(role.CommunityID)
		if !allowed[role.Name] || seen[role.Name+"|"+role.CommunityID] {
			writeAuthError(w, r, ErrInvalidAdminRole)
			return
		}
		seen[role.Name+"|"+role.CommunityID] = true
		isCommunityRole := role.Name == "community_moderator" || role.Name == "community_owner"
		if isCommunityRole != (role.CommunityID != "") {
			writeAuthError(w, r, ErrInvalidAdminRole)
			return
		}
		if role.CommunityID != "" {
			var exists bool
			if err := s.db.QueryRowContext(r.Context(), `SELECT EXISTS (SELECT 1 FROM communities WHERE id = $1 AND status = 'active' AND deleted_at IS NULL)`, role.CommunityID).Scan(&exists); err != nil || !exists {
				writeAuthError(w, r, ErrInvalidAdminRole)
				return
			}
		}
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	// 所有超级管理员角色变更先持有同一事务级锁，再检查“最后一个
	// super_admin”约束，避免两个并发降权事务分别看到对方仍存在。
	var advisoryLock any
	if err := tx.QueryRowContext(r.Context(), `SELECT pg_advisory_xact_lock(hashtext('luntan:admin-role-management'))`).Scan(&advisoryLock); err != nil {
		writeInternalError(w, r, err)
		return
	}
	// 操作者在进入 handler 后可能已经被另一笔事务降权；在锁内重新
	// 校验，避免使用过期的权限判断继续修改管理角色。
	var operatorCanManage bool
	if err := tx.QueryRowContext(r.Context(), `
		SELECT EXISTS (
			SELECT 1
			FROM user_roles ur
			JOIN roles rl ON rl.id = ur.role_id
			JOIN role_permissions rp ON rp.role_id = ur.role_id
			JOIN permissions p ON p.id = rp.permission_id
			WHERE ur.user_id = $1
			  AND rl.name = 'super_admin'
			  AND ur.community_id IS NULL
			  AND p.name = 'admin.role.manage'
		)`, operator.ID).Scan(&operatorCanManage); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if !operatorCanManage {
		writeAuthError(w, r, ErrAdminRoleManageDenied)
		return
	}
	var targetUsername, targetStatus string
	if err := tx.QueryRowContext(r.Context(), `SELECT username, status FROM users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`, targetID).Scan(&targetUsername, &targetStatus); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrInvalidAdminRole)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if targetStatus != "active" {
		writeAuthError(w, r, ErrInvalidAdminRole)
		return
	}
	oldRoles, err := readAdminRolesTx(r.Context(), tx, targetID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	oldSuper := false
	for _, role := range oldRoles {
		if role.Name == "super_admin" {
			oldSuper = true
			break
		}
	}
	newSuper := false
	for _, role := range input.Roles {
		if role.Name == "super_admin" {
			newSuper = true
			break
		}
	}
	if oldSuper && !newSuper {
		var otherSuperAdmins int64
		if err := tx.QueryRowContext(r.Context(), `SELECT count(*) FROM user_roles ur JOIN roles rl ON rl.id = ur.role_id WHERE rl.name = 'super_admin' AND ur.user_id <> $1`, targetID).Scan(&otherSuperAdmins); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if otherSuperAdmins == 0 {
			writeAuthError(w, r, ErrLastSuperAdmin)
			return
		}
	}
	if _, err := tx.ExecContext(r.Context(), `DELETE FROM user_roles WHERE user_id = $1 AND role_id IN (SELECT id FROM roles WHERE name = ANY($2::text[]))`, targetID, pqStringArray(adminRoleNames)); err != nil {
		writeInternalError(w, r, err)
		return
	}
	for _, role := range input.Roles {
		var roleID string
		if err := tx.QueryRowContext(r.Context(), `SELECT id FROM roles WHERE name = $1`, role.Name).Scan(&roleID); err != nil {
			writeAuthError(w, r, ErrInvalidAdminRole)
			return
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO user_roles (id, user_id, role_id, community_id) VALUES ($1, $2, $3, NULLIF($4, ''))`, newPostID(), targetID, roleID, role.CommunityID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	newRoles := append([]adminRoleAssignment(nil), input.Roles...)
	sort.Slice(newRoles, func(i, j int) bool {
		return newRoles[i].Name+newRoles[i].CommunityID < newRoles[j].Name+newRoles[j].CommunityID
	})
	oldRoles = append([]adminRoleAssignment(nil), oldRoles...)
	sort.Slice(oldRoles, func(i, j int) bool {
		return oldRoles[i].Name+oldRoles[i].CommunityID < oldRoles[j].Name+oldRoles[j].CommunityID
	})
	payload := map[string]any{"operator": operator.ID, "target_user": targetID, "target_username": targetUsername, "old_roles": oldRoles, "new_roles": newRoles}
	beforeJSON, _ := json.Marshal(map[string]any{"roles": oldRoles})
	afterJSON, _ := json.Marshal(map[string]any{"roles": newRoles})
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO audit_logs (id, operator_id, action, target_type, target_id, reason, before_data, after_data, request_id, created_at) VALUES ($1, $2, 'admin.roles.update', 'user', $3, $4, $5::jsonb, $6::jsonb, $7, now())`, newPostID(), operator.ID, targetID, strings.TrimSpace(input.Reason), beforeJSON, afterJSON, requestIDFromRequest(r)); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := appendAdminLogTx(r.Context(), tx, operator.ID, "admin.roles.update", "user", targetID, strings.TrimSpace(input.Reason), requestIDFromRequest(r), httpserver.ClientIP(r), payload, time.Now().UTC()); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"user_id": targetID, "roles": newRoles})
}

func readAdminRolesTx(ctx context.Context, tx *sql.Tx, userID string) ([]adminRoleAssignment, error) {
	rows, err := tx.QueryContext(ctx, `SELECT rl.name, COALESCE(ur.community_id, '') FROM user_roles ur JOIN roles rl ON rl.id = ur.role_id WHERE ur.user_id = $1 AND rl.name = ANY($2::text[])`, userID, pqStringArray(adminRoleNames))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	roles := make([]adminRoleAssignment, 0)
	for rows.Next() {
		var role adminRoleAssignment
		if err := rows.Scan(&role.Name, &role.CommunityID); err != nil {
			return nil, err
		}
		roles = append(roles, role)
	}
	return roles, rows.Err()
}

// pqStringArray 使用 PostgreSQL 的数组文本格式，避免额外引入驱动类型依赖。
func pqStringArray(values []string) string {
	quoted := make([]string, len(values))
	for index, value := range values {
		quoted[index] = `"` + strings.ReplaceAll(value, `"`, `\\"`) + `"`
	}
	return "{" + strings.Join(quoted, ",") + "}"
}

type ipRestrictionInput struct {
	CIDR         string `json:"ip_cidr"`
	Reason       string `json:"reason"`
	DurationDays int    `json:"duration_days"`
	Permanent    bool   `json:"permanent"`
}

func normalizeIPCIDR(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", ErrInvalidIPRestriction
	}
	if address, err := netip.ParseAddr(raw); err == nil {
		bits := 128
		if address.Is4() {
			bits = 32
		}
		return netip.PrefixFrom(address, bits).String(), nil
	}
	prefix, err := netip.ParsePrefix(raw)
	if err != nil {
		return "", ErrInvalidIPRestriction
	}
	return prefix.Masked().String(), nil
}

func (s *Server) listIPRestrictions(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	if _, ok := s.requireAdminRoleManager(w, r); !ok {
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `SELECT id, ip_cidr::text, reason, starts_at, ends_at, revoked_at, created_at FROM ip_restrictions ORDER BY created_at DESC LIMIT 100`)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, cidr, reason string
		var startsAt, createdAt time.Time
		var endsAt, revokedAt sql.NullTime
		if err := rows.Scan(&id, &cidr, &reason, &startsAt, &endsAt, &revokedAt, &createdAt); err != nil {
			writeInternalError(w, r, err)
			return
		}
		item := map[string]any{"id": id, "ip_cidr": cidr, "reason": reason, "starts_at": startsAt, "created_at": createdAt}
		if endsAt.Valid {
			item["ends_at"] = endsAt.Time
		}
		if revokedAt.Valid {
			item["revoked_at"] = revokedAt.Time
		}
		items = append(items, item)
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) createIPRestriction(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	operator, ok := s.requireAdminRoleManager(w, r)
	if !ok {
		return
	}
	var input ipRestrictionInput
	if err := decodeJSON(r, &input); err != nil || strings.TrimSpace(input.Reason) == "" || len([]rune(input.Reason)) > 1000 || input.DurationDays < 0 || input.DurationDays > 365 || (input.Permanent && input.DurationDays != 0) {
		writeAuthError(w, r, ErrInvalidIPRestriction)
		return
	}
	cidr, err := normalizeIPCIDR(input.CIDR)
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	var endsAt any
	if !input.Permanent && input.DurationDays > 0 {
		endsAt = time.Now().UTC().Add(time.Duration(input.DurationDays) * 24 * time.Hour)
	}
	id := newPostID()
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(r.Context(), `INSERT INTO ip_restrictions (id, ip_cidr, restriction_type, reason, starts_at, ends_at, created_by, operator_id, created_at) VALUES ($1, $2::cidr, 'access', $3, now(), $4, $5, $5, now())`, id, cidr, strings.TrimSpace(input.Reason), endsAt, operator.ID); err != nil {
		writeInternalError(w, r, err)
		return
	}
	payload := map[string]any{"ip_cidr": cidr, "permanent": input.Permanent, "duration_days": input.DurationDays}
	if err := appendAdminLogTx(r.Context(), tx, operator.ID, "ip.restriction.create", "ip_restriction", id, strings.TrimSpace(input.Reason), requestIDFromRequest(r), httpserver.ClientIP(r), payload, time.Now().UTC()); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, map[string]any{"id": id, "ip_cidr": cidr, "ends_at": endsAt})
}

func (s *Server) revokeIPRestriction(w http.ResponseWriter, r *http.Request, restrictionID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	operator, ok := s.requireAdminRoleManager(w, r)
	if !ok {
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var cidr string
	if err := tx.QueryRowContext(r.Context(), `UPDATE ip_restrictions SET revoked_at = COALESCE(revoked_at, now()), revoked_by = $2 WHERE id = $1 RETURNING ip_cidr::text`, restrictionID, operator.ID).Scan(&cidr); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrIPRestrictionNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := appendAdminLogTx(r.Context(), tx, operator.ID, "ip.restriction.revoke", "ip_restriction", restrictionID, "管理员撤销 IP 限制", requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{"ip_cidr": cidr}, time.Now().UTC()); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"id": restrictionID, "revoked": true})
}

func (s *Server) isIPRestricted(r *http.Request) bool {
	if s == nil || s.db == nil {
		return false
	}
	clientIP := httpserver.ClientIP(r)
	if clientIP == "" || clientIP == "unknown" {
		return false
	}
	var restricted bool
	err := s.db.QueryRowContext(r.Context(), `SELECT EXISTS (SELECT 1 FROM ip_restrictions WHERE restriction_type = 'access' AND revoked_at IS NULL AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now()) AND ip_cidr >>= $1::inet)`, clientIP).Scan(&restricted)
	return err == nil && restricted
}
