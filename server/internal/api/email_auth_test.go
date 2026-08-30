package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
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

	// 1. 登录场景：邮箱未注册 -> 与正常请求统一返回 202，避免账号枚举
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM users WHERE lower(email) = $1 AND account_type != 'guest' AND deleted_at IS NULL)`)).
		WithArgs("unregistered@example.com").WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	body, _ := json.Marshal(map[string]string{
		"email": "unregistered@example.com",
		"scene": "login",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/code/request", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusAccepted {
		t.Fatalf("expected status 202 for unregistered email login code request, got %d: %s", rec.Code, rec.Body.String())
	}
	var acceptedResp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &acceptedResp)
	if acceptedResp["delivery"] != "email" || acceptedResp["dev_code"] != nil {
		t.Fatalf("unexpected account-suppressed response: %#v", acceptedResp)
	}

	// 2. 注册场景：邮箱已注册 -> 使用完全相同的 202 响应
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM users WHERE lower(email) = $1 AND account_type != 'guest' AND deleted_at IS NULL)`)).
		WithArgs("registered@example.com").WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	regBody, _ := json.Marshal(map[string]string{
		"email": "registered@example.com",
		"scene": "register",
	})
	regReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/code/request", bytes.NewReader(regBody))
	regRec := httptest.NewRecorder()
	handler.ServeHTTP(regRec, regReq)

	if regRec.Code != http.StatusAccepted {
		t.Fatalf("expected status 202 for already registered email register code request, got %d: %s", regRec.Code, regRec.Body.String())
	}
	var regAcceptedResp map[string]any
	_ = json.Unmarshal(regRec.Body.Bytes(), &regAcceptedResp)
	if regAcceptedResp["delivery"] != "email" || regAcceptedResp["dev_code"] != nil {
		t.Fatalf("unexpected account-suppressed response: %#v", regAcceptedResp)
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
		       a.id, a.credential_hash,
	       (SELECT EXISTS (SELECT 1 FROM user_auth_methods pa WHERE pa.user_id = u.id AND pa.provider = 'password'))
		FROM users u
		LEFT JOIN user_auth_methods a ON a.user_id = u.id AND a.provider = 'password' AND a.identifier = $2
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE lower(u.email) = $1 AND u.account_type != 'guest' AND u.deleted_at IS NULL`)).
		WithArgs("user@example.com", "user@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "auth_id", "credential_hash", "has_password"}).
			AddRow("usr_1", "usr_1", "active", "测试用户", 1, 0, "email", "user@example.com", true, nil, "uam_1", hash, true))

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

func TestEmailPasswordLoginPasswordNotSet(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	// 账号存在但从未设置过密码（旧自动注册遗留）：应返回 PASSWORD_NOT_SET
	// 而不是笼统的密码错误，前端据此引导用户走验证码登录。
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT u.id, u.username, u.status, COALESCE(up.nickname, u.username),
	       CASE WHEN u.account_type = 'guest' THEN 0 ELSE COALESCE(up.level, 1) END,
	       COALESCE(up.experience, 0),
	       COALESCE(u.account_type, 'email'), COALESCE(u.email, ''), u.email_verified, u.email_verified_at,
	       a.id, a.credential_hash,
	       (SELECT EXISTS (SELECT 1 FROM user_auth_methods pa WHERE pa.user_id = u.id AND pa.provider = 'password'))
		FROM users u
		LEFT JOIN user_auth_methods a ON a.user_id = u.id AND a.provider = 'password' AND a.identifier = $2
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE lower(u.email) = $1 AND u.account_type != 'guest' AND u.deleted_at IS NULL`)).
		WithArgs("legacy@example.com", "legacy@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "auth_id", "credential_hash", "has_password"}).
			AddRow("usr_2", "usr_2", "active", "老用户", 1, 0, "email", "legacy@example.com", true, nil, nil, nil, false))

	body, _ := json.Marshal(map[string]string{
		"email":    "legacy@example.com",
		"password": "password123",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login/password", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected status 409 for password not set, got %d: %s", rec.Code, rec.Body.String())
	}
	var errResp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &errResp)
	if errResp["code"] != "PASSWORD_NOT_SET" {
		t.Fatalf("expected code PASSWORD_NOT_SET, got %v", errResp["code"])
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

// TestRequestEmailCodeDevFallbackMarksCodeSent 保证 dev 环境无 SMTP 时返回的 dev_code
// 对应的验证码记录处于可校验状态（sent），否则注册/登录永远无法通过校验。
func TestRequestEmailCodeDevFallbackMarksCodeSent(t *testing.T) {
	t.Setenv("ALLOW_DEV_AUTH_CODE", "true")
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM users WHERE lower(email) = $1 AND account_type != 'guest' AND deleted_at IS NULL)`)).
		WithArgs("devcode@example.com").WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT pg_advisory_xact_lock(hashtext('email-code:' || $1 || ':' || $2))`)).
		WillReturnRows(sqlmock.NewRows([]string{"pg_advisory_xact_lock"}).AddRow(nil))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM email_codes WHERE lower(email) = $1 AND purpose = $2 AND status IN ('created', 'sending', 'sent') AND consumed_at IS NULL AND created_at > now() - interval '60 seconds')`)).
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE email_codes SET consumed_at = COALESCE(consumed_at, $1)`)).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO email_codes`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO risk_events`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE email_codes SET status = 'delivery_failed', failure_reason = $1 WHERE id = $2`)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	// 修复点：dev_code 作为投递通道时，记录必须回到可校验状态
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE email_codes SET status = 'sent', sent_at = now() WHERE id = $1 AND consumed_at IS NULL`)).
		WillReturnResult(sqlmock.NewResult(1, 1))

	body, _ := json.Marshal(map[string]string{"email": "devcode@example.com", "purpose": "register"})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/code/request", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	// 必须用类型断言取值：直接比较 resp["dev_code"] == "" 在键缺失时得到
	// nil == "" 为 false，会让「响应里根本没有 dev_code」的情况被漏过。
	devCode, _ := resp["dev_code"].(string)
	if devCode == "" {
		t.Fatalf("dev 环境应返回 dev_code: %s", rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestEmailCodeDevFallbackRegisterIntegration 在真实 PostgreSQL 上验证
// dev_code 从请求到注册的完整链路（未配置 DATABASE_URL 时跳过）。
func TestEmailCodeDevFallbackRegisterIntegration(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)

	suffix := time.Now().UnixNano()
	email := fmt.Sprintf("itest-devcode-%d@example.com", suffix)
	username := fmt.Sprintf("itest_dc_%d", suffix%100000000)

	codeBody, _ := json.Marshal(map[string]string{"email": email, "purpose": "register"})
	codeReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/code/request", bytes.NewReader(codeBody))
	codeRec := httptest.NewRecorder()
	handler.ServeHTTP(codeRec, codeReq)
	if codeRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for code request, got %d: %s", codeRec.Code, codeRec.Body.String())
	}
	var codeResp map[string]any
	_ = json.Unmarshal(codeRec.Body.Bytes(), &codeResp)
	devCode, _ := codeResp["dev_code"].(string)
	if devCode == "" {
		t.Fatalf("dev 环境应返回 dev_code: %s", codeRec.Body.String())
	}

	regBody, _ := json.Marshal(map[string]string{
		"email":    email,
		"code":     devCode,
		"password": "password123",
		"nickname": "验收注册",
		"username": username,
	})
	regReq := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(regBody))
	regRec := httptest.NewRecorder()
	handler.ServeHTTP(regRec, regReq)
	if regRec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for register with dev_code, got %d: %s", regRec.Code, regRec.Body.String())
	}
	var regResp map[string]any
	_ = json.Unmarshal(regRec.Body.Bytes(), &regResp)
	if regResp["access_token"] == nil {
		t.Fatalf("missing access_token: %s", regRec.Body.String())
	}
}
