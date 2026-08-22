package auth

import (
	"context"
	"database/sql"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestRegisterCreatesPasswordCredentialAndRotatableSession(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	svc := NewService(db)
	now := time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)
	svc.clock = func() time.Time { return now }

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM users WHERE username = $1 AND deleted_at IS NULL`)).WithArgs("new_user").WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO users (id, username, status, created_at, updated_at) VALUES ($1, $2, $3, $4, $4)`)).WithArgs(sqlmock.AnyArg(), "new_user", "active", now).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO user_profiles (user_id, nickname, level, created_at, updated_at) VALUES ($1, $2, $3, $4, $4)`)).WithArgs(sqlmock.AnyArg(), "新用户", 1, now).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO user_auth_methods (id, user_id, provider, identifier, credential_hash, created_at) VALUES ($1, $2, 'password', $3, $4, $5)`)).WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), "new_user", sqlmock.AnyArg(), now).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO sessions (id, user_id, access_token_hash, expires_at, user_agent, ip_address, created_at, last_used_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $7)`)).WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), now.Add(accessTokenLifetime), "ua", "127.0.0.1", now).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO refresh_tokens (id, session_id, user_id, token_hash, expires_at, created_at, last_used_at) VALUES ($1, $2, $3, $4, $5, $6, $6)`)).WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), now.Add(refreshTokenLifetime), now).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	response, err := svc.Register(context.Background(), RegisterInput{Username: "New_User", Password: "安全密码12345", Nickname: "新用户"}, SessionMetadata{UserAgent: "ua", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	if response.User.Username != "new_user" || response.TokenType != "Bearer" || response.AccessToken == "" || response.RefreshToken == "" {
		t.Fatalf("unexpected registration response: %#v", response)
	}
	if response.AccessToken == response.RefreshToken {
		t.Fatal("access and refresh tokens must be distinct")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestLoginDoesNotRevealWhetherUsernameExistsWhenPasswordIsWrong(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	hash, err := (BcryptPasswordHasher{}).Hash("正确密码123")
	if err != nil {
		t.Fatal(err)
	}
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT u.id, u.username, u.status, COALESCE(up.nickname, u.username), COALESCE(up.level, 1), a.id, a.credential_hash`)).WithArgs("new_user").WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "auth_id", "credential_hash"}).AddRow("u1", "new_user", "active", "新用户", 1, "uam1", hash))

	_, err = NewService(db).Login(context.Background(), LoginInput{Username: "new_user", Password: "错误密码123"}, SessionMetadata{})
	if err != ErrInvalidCredentials {
		t.Fatalf("login error = %v, want ErrInvalidCredentials", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestLogoutRevokesRefreshTokenAndItsSessionIdempotently(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, now()), last_used_at = now() WHERE token_hash = $1`)).WithArgs(sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE sessions SET revoked_at = COALESCE(revoked_at, now()) WHERE id IN (SELECT session_id FROM refresh_tokens WHERE token_hash = $1)`)).WithArgs(sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	if err := NewService(db).Logout(context.Background(), "refresh-token"); err != nil {
		t.Fatal(err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
