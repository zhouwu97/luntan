package api

import (
	"context"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestGrantSuperAdminIsAuditedAndIdempotent(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	roleQuery := regexp.QuoteMeta(`SELECT id FROM roles WHERE name = 'super_admin'`)
	lockQuery := regexp.QuoteMeta(`SELECT pg_advisory_xact_lock(hashtext('luntan:admin-role-management'))`)
	targetQuery := regexp.QuoteMeta(`SELECT id, status, COALESCE(account_type, 'email'), email_verified FROM users WHERE lower(email) = $1 AND deleted_at IS NULL FOR UPDATE`)
	existsQuery := regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM user_roles WHERE user_id = $1 AND role_id = $2 AND community_id IS NULL)`)

	mock.ExpectBegin()
	mock.ExpectQuery(lockQuery).WillReturnRows(sqlmock.NewRows([]string{"lock"}).AddRow(nil))
	mock.ExpectQuery(targetQuery).WithArgs("user@example.com").WillReturnRows(sqlmock.NewRows([]string{"id", "status", "account_type", "email_verified"}).AddRow("u-target", "active", "email", true))
	mock.ExpectQuery(roleQuery).WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("role-super-admin"))
	mock.ExpectQuery(existsQuery).WithArgs("u-target", "role-super-admin").WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT u.id FROM users u JOIN user_roles ur ON ur.user_id = u.id JOIN roles rl ON rl.id = ur.role_id WHERE rl.name = 'super_admin' AND u.status = 'active' AND u.deleted_at IS NULL ORDER BY u.id LIMIT 1`)).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("u-operator"))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO user_roles (id, user_id, role_id, community_id) VALUES ($1, $2, $3, NULL) ON CONFLICT DO NOTHING`)).
		WithArgs(sqlmock.AnyArg(), "u-target", "role-super-admin").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO audit_logs (id, operator_id, action, target_type, target_id, reason, before_data, after_data, request_id, created_at) VALUES ($1, $2, 'admin.roles.update', 'user', $3, $4, '{}'::jsonb, $5::jsonb, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "u-operator", "u-target", "交付授权", `{"roles":["super_admin"]}`, "manual:grant-super-admin", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT last_hash FROM admin_log_chain WHERE id = 1 FOR UPDATE`)).
		WillReturnRows(sqlmock.NewRows([]string{"last_hash"}).AddRow("previous"))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO admin_logs (id, operator_id, action, target_type, target_id, reason, payload, previous_hash, hash, request_id, ip_address, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11, $12)`)).
		WithArgs(sqlmock.AnyArg(), "u-operator", "admin.roles.update", "user", "u-target", "交付授权", sqlmock.AnyArg(), "previous", sqlmock.AnyArg(), "manual:grant-super-admin", "", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE admin_log_chain SET last_hash = $1 WHERE id = 1`)).
		WithArgs(sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	created, err := GrantSuperAdmin(context.Background(), db, "USER@example.com", "交付授权")
	if err != nil || !created {
		t.Fatalf("首次授予结果 = (%v, %v), want (true, nil)", created, err)
	}

	mock.ExpectBegin()
	mock.ExpectQuery(lockQuery).WillReturnRows(sqlmock.NewRows([]string{"lock"}).AddRow(nil))
	mock.ExpectQuery(targetQuery).WithArgs("user@example.com").WillReturnRows(sqlmock.NewRows([]string{"id", "status", "account_type", "email_verified"}).AddRow("u-target", "active", "email", true))
	mock.ExpectQuery(roleQuery).WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("role-super-admin"))
	mock.ExpectQuery(existsQuery).WithArgs("u-target", "role-super-admin").WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))
	mock.ExpectCommit()

	created, err = GrantSuperAdmin(context.Background(), db, "user@example.com", "交付授权")
	if err != nil || created {
		t.Fatalf("重复授予结果 = (%v, %v), want (false, nil)", created, err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
