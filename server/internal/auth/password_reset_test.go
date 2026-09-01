package auth

import (
	"context"
	"database/sql"
	"errors"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestSetPasswordWithEmailCodeVerifiesInsidePasswordTransaction(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	oldHash, err := (BcryptPasswordHasher{}).Hash("原密码123456")
	if err != nil {
		t.Fatal(err)
	}

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT username, COALESCE(email, '') FROM users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`)).
		WithArgs("u1").
		WillReturnRows(sqlmock.NewRows([]string{"username", "email"}).AddRow("user1", "user@example.com"))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id, identifier, credential_hash FROM user_auth_methods WHERE user_id = $1 AND provider = 'password' FOR UPDATE`)).
		WithArgs("u1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "identifier", "credential_hash"}).AddRow("uam1", "user@example.com", oldHash))
	mock.ExpectRollback()

	verificationErr := errors.New("验证码无效")
	called := false
	err = NewService(db).SetPasswordWithEmailCode(
		context.Background(),
		"u1",
		"新密码123456",
		"user@example.com",
		"123456",
		"access-token",
		func(_ context.Context, _ *sql.Tx, email, code string) error {
			called = true
			if email != "user@example.com" || code != "123456" {
				t.Fatalf("验证码校验参数 = (%q, %q)", email, code)
			}
			return verificationErr
		},
	)
	if !errors.Is(err, verificationErr) {
		t.Fatalf("邮箱验证码错误 = %v, want %v", err, verificationErr)
	}
	if !called {
		t.Fatal("密码事务没有调用邮箱验证码校验器")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
