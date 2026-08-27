package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestRequestEmailCodeChecksScene(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	// 1. 登录场景：邮箱未注册 -> 报错 EMAIL_NOT_REGISTERED
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM users WHERE lower(email) = $1 AND account_type != 'guest' AND deleted_at IS NULL)`)).
		WithArgs("unregistered@example.com").WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	body, _ := json.Marshal(map[string]string{
		"email": "unregistered@example.com",
		"scene": "login",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/code/request", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400 for unregistered email login code request, got %d: %s", rec.Code, rec.Body.String())
	}
	var errResp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &errResp)
	if errResp["code"] != "EMAIL_NOT_REGISTERED" {
		t.Fatalf("expected code EMAIL_NOT_REGISTERED, got %v", errResp["code"])
	}

	// 2. 注册场景：邮箱已注册 -> 报错 EMAIL_ALREADY_REGISTERED (409)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM users WHERE lower(email) = $1 AND account_type != 'guest' AND deleted_at IS NULL)`)).
		WithArgs("registered@example.com").WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	regBody, _ := json.Marshal(map[string]string{
		"email": "registered@example.com",
		"scene": "register",
	})
	regReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/code/request", bytes.NewReader(regBody))
	regRec := httptest.NewRecorder()
	handler.ServeHTTP(regRec, regReq)

	if regRec.Code != http.StatusConflict {
		t.Fatalf("expected status 409 for already registered email register code request, got %d: %s", regRec.Code, regRec.Body.String())
	}
	var regErrResp map[string]any
	_ = json.Unmarshal(regRec.Body.Bytes(), &regErrResp)
	if regErrResp["code"] != "EMAIL_ALREADY_REGISTERED" {
		t.Fatalf("expected code EMAIL_ALREADY_REGISTERED, got %v", regErrResp["code"])
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestEmailPasswordLoginRoute(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	hash, _ := (auth.BcryptPasswordHasher{}).Hash("password123")

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT u.id, u.username, u.status, COALESCE(up.nickname, u.username),
		       CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
		       COALESCE(up.experience, 0),
		       COALESCE(u.account_type, 'email'), COALESCE(u.email, ''), u.email_verified, u.email_verified_at,
		       a.id, a.credential_hash
		FROM users u
		JOIN user_auth_methods a ON a.user_id = u.id AND a.provider = 'password'
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE lower(u.email) = $1 AND u.account_type != 'guest' AND u.deleted_at IS NULL`)).
		WithArgs("user@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "auth_id", "credential_hash"}).
			AddRow("usr_1", "usr_1", "active", "测试用户", 1, 0, "email", "user@example.com", true, nil, "uam_1", hash))

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE user_auth_methods SET last_used_at = $1 WHERE id = $2`)).
		WithArgs(sqlmock.AnyArg(), "uam_1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO sessions`)).WithArgs(sqlmock.AnyArg(), "usr_1", sqlmock.AnyArg(), sqlmock.AnyArg(), "", "192.0.2.1", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO refresh_tokens`)).WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), "usr_1", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	body, _ := json.Marshal(map[string]string{
		"email":    "user@example.com",
		"password": "password123",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login/password", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp["access_token"] == nil || resp["user"] == nil {
		t.Fatalf("unexpected login response: %s", rec.Body.String())
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestEmailRegisterRouteValidatesCodeAndCreatesUser(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	codeHash := emailCodeHash("123456")

	// 1. 验证码校验
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id, code_hash, expires_at, attempts FROM email_codes WHERE lower(email) = $1 AND purpose = $2 AND status IN ('created', 'sending', 'sent') AND consumed_at IS NULL ORDER BY created_at DESC, id DESC LIMIT 1 FOR UPDATE`)).
		WithArgs("newuser@example.com", "register").
		WillReturnRows(sqlmock.NewRows([]string{"id", "code_hash", "expires_at", "attempts"}).AddRow("code_1", codeHash, time.Now().Add(5*time.Minute), 0))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE email_codes SET consumed_at = now(), status = 'verified', verified_at = now() WHERE id = $1`)).
		WithArgs("code_1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO risk_events`)).WithArgs(sqlmock.AnyArg(), "192.0.2.1", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	// 2. 账号创建
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM users WHERE lower(email) = $1 AND account_type != 'guest' AND deleted_at IS NULL FOR UPDATE`)).
		WithArgs("newuser@example.com").WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO users (id, username, status, email, email_verified, email_verified_at, account_type, created_at, updated_at)`)).
		WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), "newuser@example.com", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO user_profiles (user_id, nickname, level, experience, created_at, updated_at)`)).
		WithArgs(sqlmock.AnyArg(), "新人小明", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO user_auth_methods (id, user_id, provider, identifier, credential_hash, created_at)`)).
		WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), "newuser@example.com", sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO sessions`)).WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), "", "192.0.2.1", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO refresh_tokens`)).WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	body, _ := json.Marshal(map[string]string{
		"email":    "newuser@example.com",
		"code":     "123456",
		"password": "password123",
		"nickname": "新人小明",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp["access_token"] == nil {
		t.Fatalf("missing access_token in response: %s", rec.Body.String())
	}
	userMap, ok := resp["user"].(map[string]any)
	if !ok || userMap["email"] != "newuser@example.com" || userMap["nickname"] != "新人小明" {
		t.Fatalf("unexpected user in response: %#v", resp["user"])
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
