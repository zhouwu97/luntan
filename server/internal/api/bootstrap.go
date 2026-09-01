package api

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
)

var (
	ErrBootstrapEmailRequired = errors.New("bootstrap admin email is required")
	ErrBootstrapUserNotFound  = errors.New("bootstrap admin user not found")
)

// GrantSuperAdmin 将一个已存在、已验证且处于 active 状态的正式邮箱账号
// 授予 super_admin。它与首次初始化流程分开，允许在已有超级管理员时安全
// 增加管理员；操作具备事务、幂等和 append-only 审计记录。
func GrantSuperAdmin(ctx context.Context, db *sql.DB, email, reason string) (created bool, err error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return false, ErrBootstrapEmailRequired
	}
	if db == nil {
		return false, errors.New("database is not configured")
	}
	reason = strings.TrimSpace(reason)
	if reason == "" {
		reason = "交付验收请求授予超级管理员"
	}

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	var lock any
	if err := tx.QueryRowContext(ctx, `SELECT pg_advisory_xact_lock(hashtext('luntan:admin-role-management'))`).Scan(&lock); err != nil {
		return false, err
	}

	var targetID, status, accountType string
	var emailVerified bool
	err = tx.QueryRowContext(ctx, `SELECT id, status, COALESCE(account_type, 'email'), email_verified FROM users WHERE lower(email) = $1 AND deleted_at IS NULL FOR UPDATE`, email).Scan(&targetID, &status, &accountType, &emailVerified)
	if errors.Is(err, sql.ErrNoRows) {
		return false, ErrBootstrapUserNotFound
	}
	if err != nil {
		return false, err
	}
	if status != "active" || accountType == "guest" || !emailVerified {
		return false, ErrBootstrapUserNotFound
	}

	var roleID string
	if err := tx.QueryRowContext(ctx, `SELECT id FROM roles WHERE name = 'super_admin'`).Scan(&roleID); err != nil {
		return false, fmt.Errorf("super_admin role is unavailable: %w", err)
	}
	var alreadyGranted bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM user_roles WHERE user_id = $1 AND role_id = $2 AND community_id IS NULL)`, targetID, roleID).Scan(&alreadyGranted); err != nil {
		return false, err
	}
	if alreadyGranted {
		return false, tx.Commit()
	}

	operatorID := targetID
	if err := tx.QueryRowContext(ctx, `SELECT u.id FROM users u JOIN user_roles ur ON ur.user_id = u.id JOIN roles rl ON rl.id = ur.role_id WHERE rl.name = 'super_admin' AND u.status = 'active' AND u.deleted_at IS NULL ORDER BY u.id LIMIT 1`).Scan(&operatorID); errors.Is(err, sql.ErrNoRows) {
		// 首个管理员授予时没有其他操作者，使用目标账号作为初始化审计主体，
		// 与 BootstrapSuperAdmin 的历史语义保持一致。
		operatorID = targetID
	} else if err != nil {
		return false, err
	}

	if _, err := tx.ExecContext(ctx, `INSERT INTO user_roles (id, user_id, role_id, community_id) VALUES ($1, $2, $3, NULL) ON CONFLICT DO NOTHING`, newPostID(), targetID, roleID); err != nil {
		return false, err
	}
	now := time.Now().UTC()
	afterData := `{"roles":["super_admin"]}`
	if _, err := tx.ExecContext(ctx, `INSERT INTO audit_logs (id, operator_id, action, target_type, target_id, reason, before_data, after_data, request_id, created_at) VALUES ($1, $2, 'admin.roles.update', 'user', $3, $4, '{}'::jsonb, $5::jsonb, $6, $7)`, newPostID(), operatorID, targetID, reason, afterData, "manual:grant-super-admin", now); err != nil {
		return false, err
	}
	payload := map[string]any{
		"operator":    operatorID,
		"target_user": targetID,
		"old_roles":   []string{},
		"new_roles":   []string{"super_admin"},
	}
	if err := appendAdminLogTx(ctx, tx, operatorID, "admin.roles.update", "user", targetID, reason, "manual:grant-super-admin", "", payload, now); err != nil {
		return false, err
	}
	if err := tx.Commit(); err != nil {
		return false, err
	}
	return true, nil
}

// BootstrapSuperAdmin 只允许在当前数据库尚无超级管理员时，把一个已存在且已验证
// 的邮箱账号提升为超级管理员。它不创建新账号，重复执行是幂等的。
func BootstrapSuperAdmin(ctx context.Context, db *sql.DB, email string) (created bool, err error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return false, ErrBootstrapEmailRequired
	}
	if db == nil {
		return false, errors.New("database is not configured")
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	var lock any
	if err := tx.QueryRowContext(ctx, `SELECT pg_advisory_xact_lock(hashtext('luntan:bootstrap-super-admin'))`).Scan(&lock); err != nil {
		return false, err
	}
	var count int
	if err := tx.QueryRowContext(ctx, `SELECT count(*) FROM user_roles ur JOIN roles rl ON rl.id = ur.role_id WHERE rl.name = 'super_admin'`).Scan(&count); err != nil {
		return false, err
	}
	if count > 0 {
		return false, tx.Commit()
	}
	var userID string
	if err := tx.QueryRowContext(ctx, `SELECT id FROM users WHERE lower(email) = $1 AND email_verified = true AND deleted_at IS NULL AND status = 'active' FOR UPDATE`, email).Scan(&userID); errors.Is(err, sql.ErrNoRows) {
		return false, ErrBootstrapUserNotFound
	} else if err != nil {
		return false, err
	}
	var roleID string
	if err := tx.QueryRowContext(ctx, `SELECT id FROM roles WHERE name = 'super_admin'`).Scan(&roleID); err != nil {
		return false, fmt.Errorf("super_admin role is unavailable: %w", err)
	}
	now := time.Now().UTC()
	if _, err := tx.ExecContext(ctx, `INSERT INTO user_roles (id, user_id, role_id, community_id) VALUES ($1, $2, $3, NULL) ON CONFLICT DO NOTHING`, newPostID(), userID, roleID); err != nil {
		return false, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO audit_logs (id, operator_id, action, target_type, target_id, reason, before_data, after_data, request_id, created_at) VALUES ($1, $2, 'admin.bootstrap', 'user', $2, '首次初始化超级管理员', '{}'::jsonb, $3::jsonb, '', $4)`, newPostID(), userID, `{"roles":["super_admin"]}`, now); err != nil {
		return false, err
	}
	if err := appendAdminLogTx(ctx, tx, userID, "admin.bootstrap", "user", userID, "首次初始化超级管理员", "", "", map[string]any{"roles": []string{"super_admin"}}, now); err != nil {
		return false, err
	}
	if err := tx.Commit(); err != nil {
		return false, err
	}
	return true, nil
}
