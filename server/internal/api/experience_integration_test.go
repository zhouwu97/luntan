package api

import (
	"context"
	"database/sql"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestGuestUpgradeInPlaceWhenEmailIsNew(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	svc := auth.NewService(db)
	now := time.Date(2026, 8, 27, 12, 0, 0, 0, time.UTC)

	mock.ExpectBegin()
	// 1. 检查邮箱是否已存在 -> 返回 ErrNoRows
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM users WHERE lower(email) = $1 AND account_type != 'guest' AND deleted_at IS NULL FOR UPDATE`)).WithArgs("newuser@example.com").WillReturnError(sql.ErrNoRows)

	// 2. 查询当前游客信息 (有 860 EXP)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT u.username, u.status, COALESCE(up.nickname, u.username), COALESCE(up.experience, 0)
			FROM users u
			LEFT JOIN user_profiles up ON up.user_id = u.id
			WHERE u.id = $1 AND u.account_type = 'guest' AND u.deleted_at IS NULL
			FOR UPDATE OF u`)).WithArgs("usr_guest123").WillReturnRows(sqlmock.NewRows([]string{"username", "status", "nickname", "experience"}).AddRow("guest_abc", "active", "杯友_1234", int64(860)))

	// 3. 原地升级 users 表
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET account_type = 'email', email = $1, email_verified = true, email_verified_at = $2, updated_at = $2 WHERE id = $3`)).
		WithArgs("newuser@example.com", sqlmock.AnyArg(), "usr_guest123").WillReturnResult(sqlmock.NewResult(1, 1))

	// 4. 原地升级 user_profiles 表 (860 EXP 对应 Lv.4)
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE user_profiles SET nickname = $1, level = $2, updated_at = $3 WHERE user_id = $4`)).
		WithArgs("杯友_1234", 4, sqlmock.AnyArg(), "usr_guest123").WillReturnResult(sqlmock.NewResult(1, 1))

	// 5. 写入密码凭证
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO user_auth_methods (id, user_id, provider, identifier, credential_hash, created_at) VALUES ($1, $2, 'password', $3, $4, $5)`)).
		WithArgs(sqlmock.AnyArg(), "usr_guest123", "newuser@example.com", sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))

	// 6. 创建 session
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO sessions`)).WithArgs(sqlmock.AnyArg(), "usr_guest123", sqlmock.AnyArg(), sqlmock.AnyArg(), "ua", "127.0.0.1", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO refresh_tokens`)).WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), "usr_guest123", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	resp, err := svc.RegisterWithEmail(context.Background(), auth.EmailRegisterInput{
		Email:       "newuser@example.com",
		Password:    "password123",
		Nickname:    "",
		GuestUserID: "usr_guest123",
	}, auth.SessionMetadata{UserAgent: "ua", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatalf("RegisterWithEmail failed: %v", err)
	}

	if resp.User.ID != "usr_guest123" {
		t.Errorf("expected user ID to stay usr_guest123, got %s", resp.User.ID)
	}
	if resp.User.AccountType != "email" {
		t.Errorf("expected account_type email, got %s", resp.User.AccountType)
	}
	if resp.User.Level != 4 {
		t.Errorf("expected level 4 for 860 EXP, got %d", resp.User.Level)
	}
	if !resp.User.EmailVerified {
		t.Errorf("expected email_verified true, got %v", resp.User.EmailVerified)
	}

	_ = now
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestGuestLoginExistingEmailDoesNotMergeGuestExp(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	svc := auth.NewService(db)

	mock.ExpectBegin()
	// 1. 邮箱已有正式账号 (已有账号 EXP 100, Lv.2)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT u.id, u.username, u.status, COALESCE(up.nickname, u.username),
		       CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
		       COALESCE(u.account_type, 'email'), u.email, u.email_verified, u.email_verified_at,
		       COALESCE(up.experience, 0),
		       (SELECT EXISTS (SELECT 1 FROM user_auth_methods pa WHERE pa.user_id = u.id AND pa.provider = 'password'))
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE lower(u.email) = $1 AND u.account_type != 'guest' AND u.deleted_at IS NULL
		FOR UPDATE OF u`)).WithArgs("existing@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "account_type", "email", "email_verified", "email_verified_at", "experience", "has_password"}).
			AddRow("usr_existing_456", "existing_user", "active", "老用户", 2, "email", "existing@example.com", true, nil, int64(100), false))

	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET email_verified = true, email_verified_at = COALESCE(email_verified_at, $1), updated_at = $1 WHERE id = $2`)).
		WithArgs(sqlmock.AnyArg(), "usr_existing_456").WillReturnResult(sqlmock.NewResult(1, 1))

	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO sessions`)).WithArgs(sqlmock.AnyArg(), "usr_existing_456", sqlmock.AnyArg(), sqlmock.AnyArg(), "ua", "127.0.0.1", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO refresh_tokens`)).WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), "usr_existing_456", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	// 游客调用 EmailCodeLogin 登录已有正式账号
	resp, err := svc.EmailCodeLogin(context.Background(), "existing@example.com", auth.SessionMetadata{UserAgent: "ua", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatalf("EmailCodeLogin failed: %v", err)
	}

	// 必须登录老账户 usr_existing_456，不合并游客
	if resp.User.ID != "usr_existing_456" {
		t.Errorf("expected user ID usr_existing_456, got %s", resp.User.ID)
	}
	if resp.User.Level != 2 {
		t.Errorf("expected existing level 2, got %d", resp.User.Level)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
