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

	if _, err := NewService(db).Refresh(context.Background(), response.RefreshToken, SessionMetadata{}); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("reusing the old refresh token error = %v, want ErrInvalidToken", err)
	}
}
