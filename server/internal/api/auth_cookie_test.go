package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func findCookie(t *testing.T, cookies []*http.Cookie, name string) *http.Cookie {
	t.Helper()
	for _, cookie := range cookies {
		if cookie.Name == name {
			return cookie
		}
	}
	return nil
}

func TestLoginPasswordSetsRefreshTokenCookie(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	hash, _ := (auth.BcryptPasswordHasher{}).Hash("password123")
	mock.ExpectQuery("SELECT u\\.id, u\\.username, u\\.status").
		WithArgs("user@example.com", "user@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "auth_id", "credential_hash", "has_password"}).
			AddRow("usr_1", "usr_1", "active", "测试用户", 1, 0, "email", "user@example.com", true, nil, "uam_1", hash, true))
	mock.ExpectBegin()
	mock.ExpectExec("UPDATE user_auth_methods SET last_used_at").
		WithArgs(sqlmock.AnyArg(), "uam_1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO sessions").
		WithArgs(sqlmock.AnyArg(), "usr_1", sqlmock.AnyArg(), sqlmock.AnyArg(), "", "192.0.2.1", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO refresh_tokens").
		WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), "usr_1", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	body, _ := json.Marshal(map[string]string{
		"email":    "user@example.com",
		"password": "password123",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login/password", bytes.NewReader(body))
	// 生产部署由 nginx 终结 TLS，Cookie 必须依据转发协议开启 Secure。
	req.Header.Set("X-Forwarded-Proto", "https")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp["access_token"] == "" || resp["refresh_token"] == "" {
		t.Fatalf("body 必须保留 token 供原生客户端使用: %s", rec.Body.String())
	}

	cookie := findCookie(t, rec.Result().Cookies(), refreshTokenCookieName)
	if cookie == nil {
		t.Fatal("登录响应必须设置 refresh token Cookie")
	}
	if !cookie.HttpOnly || !cookie.Secure {
		t.Fatalf("cookie 必须 HttpOnly + Secure，got: %#v", cookie)
	}
	if cookie.Path != "/api/v1/auth" {
		t.Fatalf("cookie path = %q", cookie.Path)
	}
	if cookie.MaxAge != 30*24*60*60 {
		t.Fatalf("cookie max-age = %d", cookie.MaxAge)
	}
	if cookie.Value == "" {
		t.Fatal("cookie value 为空")
	}
}

func TestRefreshViaCookieOmitsBodyRefreshToken(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT rt\\.id, rt\\.session_id").
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "session_id", "user_id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "expires_at", "has_password"}).
			AddRow("rft_old", "sess_1", "usr_1", "usr_1", "active", "测试用户", 1, 0, "email", "user@example.com", true, nil, time.Now().Add(24*time.Hour), false))
	mock.ExpectExec("UPDATE refresh_tokens SET revoked_at").
		WithArgs(sqlmock.AnyArg(), "rft_old").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("UPDATE sessions SET access_token_hash").
		WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg(), "sess_1").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO refresh_tokens").
		WithArgs(sqlmock.AnyArg(), "sess_1", "usr_1", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("UPDATE refresh_tokens SET replaced_by_id").
		WithArgs(sqlmock.AnyArg(), "rft_old").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	body, _ := json.Marshal(map[string]string{"refresh_token": ""})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/refresh", bytes.NewReader(body))
	req.AddCookie(&http.Cookie{Name: refreshTokenCookieName, Value: "raw-cookie-token"})
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp["access_token"] == "" {
		t.Fatalf("missing access_token: %s", rec.Body.String())
	}
	if value, ok := resp["refresh_token"].(string); ok && value != "" {
		t.Fatalf("cookie 刷新的响应体不得携带 refresh token: %q", value)
	}

	cookie := findCookie(t, rec.Result().Cookies(), refreshTokenCookieName)
	if cookie == nil || cookie.Value == "" {
		t.Fatal("轮换后的 refresh token 必须通过 Set-Cookie 下发")
	}
	if !cookie.HttpOnly {
		t.Fatal("轮换 Cookie 必须保持 HttpOnly")
	}
}

func TestRefreshWithoutBodyTokenOrCookieIsRejected(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	body, _ := json.Marshal(map[string]string{"refresh_token": ""})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/refresh", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d: %s", rec.Code, rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("不应触发数据库访问: %v", err)
	}
}

func TestLogoutWithoutTokenStillClearsCookie(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	handler := NewHandler(db)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/logout", bytes.NewReader([]byte("{}")))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d: %s", rec.Code, rec.Body.String())
	}
	cookie := findCookie(t, rec.Result().Cookies(), refreshTokenCookieName)
	if cookie == nil || cookie.MaxAge >= 0 {
		t.Fatalf("logout 必须清除 refresh token Cookie，got: %#v", cookie)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("无 token 登出不应触发数据库访问: %v", err)
	}
}
