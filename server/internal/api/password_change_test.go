package api

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestSetPasswordRejectsMixedVerificationMethods(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	server := NewHandler(db).(*Server)
	requestBody, err := json.Marshal(map[string]string{
		"password":         "新密码123456",
		"current_password": "原密码123456",
		"email_code":       "123456",
	})
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/me/password", bytes.NewReader(requestBody))
	request = request.WithContext(context.WithValue(request.Context(), authenticatedUserContextKey{}, auth.User{
		ID:            "u1",
		AccountType:   "email",
		Email:         "user@example.com",
		EmailVerified: true,
		Status:        "active",
	}))
	response := httptest.NewRecorder()
	server.setPassword(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("同时提交两种验证方式的状态码 = %d, want 400: %s", response.Code, response.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestSetPasswordRejectsEmailCodeForUnverifiedEmail(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	server := NewHandler(db).(*Server)
	requestBody, err := json.Marshal(map[string]string{
		"password":   "新密码123456",
		"email_code": "123456",
	})
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/me/password", bytes.NewReader(requestBody))
	request = request.WithContext(context.WithValue(request.Context(), authenticatedUserContextKey{}, auth.User{
		ID:            "u1",
		AccountType:   "email",
		Email:         "user@example.com",
		EmailVerified: false,
		Status:        "active",
	}))
	response := httptest.NewRecorder()
	server.setPassword(response, request)

	if response.Code != http.StatusForbidden {
		t.Fatalf("未验证邮箱的验证码改密状态码 = %d, want 403: %s", response.Code, response.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestSetPasswordWithEmailCodeConsumesCodeAndRevokesOtherSessions(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	server := NewHandler(db).(*Server)
	oldHash, err := (auth.BcryptPasswordHasher{}).Hash("原密码123456")
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
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id, code_hash, expires_at, attempts FROM email_codes WHERE lower(email) = $1 AND purpose = $2 AND status IN ('created', 'sending', 'sent') AND consumed_at IS NULL ORDER BY created_at DESC, id DESC LIMIT 1 FOR UPDATE`)).
		WithArgs("user@example.com", "password_reset").
		WillReturnRows(sqlmock.NewRows([]string{"id", "code_hash", "expires_at", "attempts"}).AddRow("code1", server.emailCodeHash("123456"), time.Now().UTC().Add(time.Minute), 0))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE email_codes SET consumed_at = now(), status = 'verified', verified_at = now() WHERE id = $1`)).
		WithArgs("code1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE user_auth_methods SET credential_hash = $2 WHERE id = $1`)).
		WithArgs("uam1", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM sessions WHERE user_id = $1 AND access_token_hash = $2 AND revoked_at IS NULL`)).
		WithArgs("u1", sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("ses-current"))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE sessions SET revoked_at = COALESCE(revoked_at, now()) WHERE user_id = $1 AND revoked_at IS NULL AND id <> $2`)).
		WithArgs("u1", "ses-current").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE refresh_tokens SET revoked_at = COALESCE(revoked_at, now()) WHERE user_id = $1 AND revoked_at IS NULL AND session_id <> $2`)).
		WithArgs("u1", "ses-current").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	requestBody, err := json.Marshal(map[string]string{
		"password":   "新密码123456",
		"email_code": "123456",
	})
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/me/password", bytes.NewReader(requestBody))
	request.Header.Set("Authorization", "Bearer access-token")
	request = request.WithContext(context.WithValue(request.Context(), authenticatedUserContextKey{}, auth.User{
		ID:            "u1",
		AccountType:   "email",
		Email:         "user@example.com",
		EmailVerified: true,
		Status:        "active",
	}))
	response := httptest.NewRecorder()
	server.setPassword(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("邮箱验证码改密状态码 = %d, want 204: %s", response.Code, response.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestPasswordResetCodeRequestRequiresAuthenticatedAccount(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	server := NewHandler(db)
	requestBody, err := json.Marshal(map[string]string{
		"email": "user@example.com",
		"scene": "password_reset",
	})
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/email/request", bytes.NewReader(requestBody))
	response := httptest.NewRecorder()
	server.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("未登录密码重置验证码请求状态码 = %d, want 401: %s", response.Code, response.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
