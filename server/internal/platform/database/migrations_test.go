package database

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestMigrationFilesAreOrderedAndPaired(t *testing.T) {
	directory := filepath.Join("..", "..", "..", "migrations")
	files, err := ListUpMigrations(directory)
	if err != nil {
		t.Fatal(err)
	}
	// 版本必须从 000001 起连续无缺口，且全部为升序。
	// 这里刻意不写死迁移总数，否则每新增一个迁移都要修改本测试。
	if len(files) == 0 {
		t.Fatal("未发现任何 up 迁移文件")
	}
	for i, file := range files {
		want := fmt.Sprintf("%06d", i+1)
		if file.Version != want {
			t.Fatalf("迁移版本不连续：第 %d 个迁移版本为 %s，期望 %s（全部：%d 个）", i+1, file.Version, want, len(files))
		}
	}
	for _, file := range files {
		entries, err := os.ReadDir(directory)
		if err != nil {
			t.Fatal(err)
		}
		foundDown := false
		baseName := strings.TrimSuffix(filepath.Base(file.Path), ".up.sql")
		for _, entry := range entries {
			if entry.Name() == baseName+".down.sql" {
				foundDown = true
				break
			}
		}
		if !foundDown {
			t.Fatalf("down migration missing for %s", file.Path)
		}
	}
}

func TestMigrationsAgainstPostgres(t *testing.T) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL 未配置，跳过真实 PostgreSQL Migration 集成测试")
	}
	db, err := Open(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	if err := Migrate(ctx, db, filepath.Join("..", "..", "..", "migrations")); err != nil {
		t.Fatal(err)
	}
	if err := Migrate(ctx, db, filepath.Join("..", "..", "..", "migrations")); err != nil {
		t.Fatal(err)
	}
	var hasDirtyColumn bool
	if err := db.QueryRowContext(ctx, `SELECT EXISTS (
		SELECT 1 FROM information_schema.columns
		WHERE table_schema = 'public' AND table_name = 'schema_migrations' AND column_name = 'dirty'
	)`).Scan(&hasDirtyColumn); err != nil {
		t.Fatal(err)
	}
	if !hasDirtyColumn {
		t.Fatal("schema_migrations 缺少 dirty 列")
	}
	var dirtyCount int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM schema_migrations WHERE dirty`).Scan(&dirtyCount); err != nil {
		t.Fatal(err)
	}
	if dirtyCount != 0 {
		t.Fatalf("schema_migrations 存在 dirty 记录: %d", dirtyCount)
	}
	for _, table := range []string{"users", "user_profiles", "community_categories", "communities", "posts", "user_auth_methods", "sessions", "refresh_tokens", "post_revisions", "post_idempotency_keys", "media_assets", "media_variants", "media_moderation_versions", "post_media", "comments", "comment_idempotency_keys", "post_reactions", "comment_reactions", "bookmarks", "bookmark_folders", "bookmark_folder_items", "user_follows", "community_follows", "community_members", "notifications", "reports", "moderation_cases", "moderation_actions", "roles", "permissions", "role_permissions", "user_roles", "audit_logs", "blocks", "outbox_events", "point_transactions", "experience_transactions", "polls", "poll_options", "poll_votes", "market_items", "user_post_histories", "store_products", "store_orders", "store_order_shipping", "store_point_invalidations", "moderation_appeals", "moderation_appeal_media", "ranking_toys", "ranking_toy_user_states", "ranking_toy_rating_distribution", "ranking_toy_comments", "ranking_toy_comment_likes", "email_codes", "guest_sessions", "bans", "restrictions", "admin_invites", "login_devices", "risk_events", "admin_log_chain", "admin_logs", "ip_restrictions", "home_recommendations", "ranking_toy_submissions"} {
		var exists bool
		if err := db.QueryRowContext(ctx, `SELECT to_regclass($1) IS NOT NULL`, "public."+table).Scan(&exists); err != nil {
			t.Fatal(err)
		}
		if !exists {
			t.Fatalf("table %s does not exist", table)
		}
	}
}

func TestMigrateSerializesIndependentDatabaseConnections(t *testing.T) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL 未配置，跳过跨连接 Migration 并发集成测试")
	}

	db1, err := Open(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db1.Close()
	db2, err := Open(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db2.Close()

	ctx := context.Background()
	if err := db1.PingContext(ctx); err != nil {
		t.Fatal(err)
	}
	if err := db2.PingContext(ctx); err != nil {
		t.Fatal(err)
	}

	directory := filepath.Join("..", "..", "..", "migrations")
	start := make(chan struct{})
	results := make(chan error, 2)
	var group sync.WaitGroup
	for _, db := range []*sql.DB{db1, db2} {
		group.Add(1)
		go func(connection *sql.DB) {
			defer group.Done()
			<-start
			results <- Migrate(ctx, connection, directory)
		}(db)
	}
	close(start)
	group.Wait()
	close(results)

	for err := range results {
		if err != nil {
			t.Fatalf("并发 Migration 失败: %v", err)
		}
	}

	files, err := ListUpMigrations(directory)
	if err != nil {
		t.Fatal(err)
	}
	var appliedCount int
	if err := db1.QueryRowContext(ctx, `SELECT COUNT(*) FROM schema_migrations`).Scan(&appliedCount); err != nil {
		t.Fatal(err)
	}
	if appliedCount != len(files) {
		t.Fatalf("schema_migrations 记录数=%d，期望=%d", appliedCount, len(files))
	}
	var duplicateCount int
	if err := db1.QueryRowContext(ctx, `
		SELECT COUNT(*) - COUNT(DISTINCT version)
		FROM schema_migrations
	`).Scan(&duplicateCount); err != nil {
		t.Fatal(err)
	}
	if duplicateCount != 0 {
		t.Fatalf("schema_migrations 存在重复版本: %d", duplicateCount)
	}
}
