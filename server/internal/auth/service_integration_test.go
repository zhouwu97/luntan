package auth

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/database"
)

// TestRefreshRotatesTokenAgainstPostgres 使用真实数据库锁定刷新令牌轮换顺序。
// 未配置 DATABASE_URL 时跳过，保持默认 go test 不依赖本地 PostgreSQL。
func TestRefreshRotatesTokenAgainstPostgres(t *testing.T) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL 未配置，跳过真实 PostgreSQL Auth 集成测试")
	}

	db, err := database.Open(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	if err := database.Migrate(context.Background(), db, filepath.Join("..", "..", "migrations")); err != nil {
		t.Fatal(err)
	}

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	response, err := NewService(db).Register(context.Background(), RegisterInput{
		Username: "auth_refresh_" + suffix,
		Password: "安全密码12345",
		Nickname: "刷新测试",
	}, SessionMetadata{UserAgent: "auth-integration-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		// 测试用户没有业务数据，按外键依赖顺序清理即可。
		for _, query := range []string{
			`DELETE FROM risk_events WHERE user_id = $1`,
			`DELETE FROM refresh_tokens WHERE user_id = $1`,
			`DELETE FROM sessions WHERE user_id = $1`,
			`DELETE FROM user_auth_methods WHERE user_id = $1`,
			`DELETE FROM user_profiles WHERE user_id = $1`,
			`DELETE FROM users WHERE id = $1`,
		} {
			_, _ = db.Exec(query, response.User.ID)
		}
	})

	rotated, err := NewService(db).Refresh(context.Background(), response.RefreshToken, SessionMetadata{
		UserAgent: "auth-integration-test/refresh",
		IPAddress: "127.0.0.1",
	})
	if err != nil {
		t.Fatalf("refresh should rotate a valid token: %v", err)
	}
	if rotated.RefreshToken == response.RefreshToken || rotated.AccessToken == response.AccessToken {
		t.Fatal("refresh rotation must issue new access and refresh tokens")
	}

	var replacedBy string
	if err := db.QueryRow(
		`SELECT replaced_by_id FROM refresh_tokens WHERE token_hash = $1`,
		tokenHash(response.RefreshToken),
	).Scan(&replacedBy); err != nil {
		t.Fatal(err)
	}
	var replacementID string
	if err := db.QueryRow(
		`SELECT id FROM refresh_tokens WHERE token_hash = $1`,
		tokenHash(rotated.RefreshToken),
	).Scan(&replacementID); err != nil {
		t.Fatal(err)
	}
	if replacedBy != replacementID {
		t.Fatalf("replaced_by_id = %q, want %q", replacedBy, replacementID)
	}

	// 旧 token 重放：判定该 session 族泄漏，整个 session（含最新 token）都应被撤销。
	if _, err := NewService(db).Refresh(context.Background(), response.RefreshToken, SessionMetadata{}); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("reusing the old refresh token error = %v, want ErrInvalidToken", err)
	}
	sessionIDOf := func(tokenHashValue string) string {
		t.Helper()
		var sessionID string
		if err := db.QueryRow(`SELECT session_id FROM refresh_tokens WHERE token_hash = $1`, tokenHashValue).Scan(&sessionID); err != nil {
			t.Fatal(err)
		}
		return sessionID
	}
	familySessionID := sessionIDOf(tokenHash(rotated.RefreshToken))
	var pendingTokens int
	if err := db.QueryRow(`SELECT COUNT(*) FROM refresh_tokens WHERE session_id = $1 AND revoked_at IS NULL`, familySessionID).Scan(&pendingTokens); err != nil {
		t.Fatal(err)
	}
	if pendingTokens != 0 {
		t.Fatalf("重放后该 session 仍有 %d 个未撤销的 refresh token", pendingTokens)
	}
	var activeSessions int
	if err := db.QueryRow(`SELECT COUNT(*) FROM sessions WHERE id = $1 AND revoked_at IS NULL`, familySessionID).Scan(&activeSessions); err != nil {
		t.Fatal(err)
	}
	if activeSessions != 0 {
		t.Fatal("重放后 session 未被撤销")
	}
	var riskEvents int
	if err := db.QueryRow(`SELECT COUNT(*) FROM risk_events WHERE event_type = 'refresh_token_replay' AND metadata->>'session_id' = $1`, familySessionID).Scan(&riskEvents); err != nil {
		t.Fatal(err)
	}
	if riskEvents == 0 {
		t.Fatal("重放未写入 risk_events 审计")
	}
	// 重放后连最新的 refresh token 也必须失效。
	if _, err := NewService(db).Refresh(context.Background(), rotated.RefreshToken, SessionMetadata{}); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("重放撤销后最新 token 也应失效: %v", err)
	}
}

// 修改密码必须撤销既有会话，否则已泄漏的 refresh token 在改密后仍然可用。
func TestSetPasswordRevokesOtherSessionsAgainstPostgres(t *testing.T) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL 未配置，跳过真实 PostgreSQL Auth 集成测试")
	}

	db, err := database.Open(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	if err := database.Migrate(context.Background(), db, filepath.Join("..", "..", "migrations")); err != nil {
		t.Fatal(err)
	}

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	svc := NewService(db)
	response, err := svc.Register(context.Background(), RegisterInput{
		Username: "auth_password_" + suffix,
		Password: "安全密码12345",
		Nickname: "改密测试",
	}, SessionMetadata{UserAgent: "auth-integration-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, query := range []string{
			`DELETE FROM refresh_tokens WHERE user_id = $1`,
			`DELETE FROM sessions WHERE user_id = $1`,
			`DELETE FROM user_auth_methods WHERE user_id = $1`,
			`DELETE FROM user_profiles WHERE user_id = $1`,
			`DELETE FROM users WHERE id = $1`,
		} {
			_, _ = db.Exec(query, response.User.ID)
		}
	})

	// 第二台"设备"独立登录。
	other, err := svc.Login(context.Background(), LoginInput{
		Username: "auth_password_" + suffix,
		Password: "安全密码12345",
	}, SessionMetadata{UserAgent: "auth-integration-test/other-device", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	if err := svc.SetPassword(context.Background(), response.User.ID, "新密码123456", "安全密码12345", response.AccessToken); err != nil {
		t.Fatalf("set password: %v", err)
	}

	// 其他设备的 refresh token 必须已失效。
	if _, err := svc.Refresh(context.Background(), other.RefreshToken, SessionMetadata{}); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("other session refresh after password change error = %v, want ErrInvalidToken", err)
	}
	// 当前会话保持可用，可继续轮换。
	rotated, err := svc.Refresh(context.Background(), response.RefreshToken, SessionMetadata{
		UserAgent: "auth-integration-test/current",
		IPAddress: "127.0.0.1",
	})
	if err != nil {
		t.Fatalf("current session refresh after password change: %v", err)
	}
	if rotated.AccessToken == "" || rotated.RefreshToken == "" {
		t.Fatal("current session refresh must return a fresh token pair")
	}

	// 旧密码不能再登录，新密码可以。
	if _, err := svc.Login(context.Background(), LoginInput{Username: "auth_password_" + suffix, Password: "安全密码12345"}, SessionMetadata{}); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("login with old password error = %v, want ErrInvalidCredentials", err)
	}
	if _, err := svc.Login(context.Background(), LoginInput{Username: "auth_password_" + suffix, Password: "新密码123456"}, SessionMetadata{}); err != nil {
		t.Fatalf("login with new password: %v", err)
	}
}
