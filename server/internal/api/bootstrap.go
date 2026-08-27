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
