package database

import (
	"context"
	"database/sql"
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
	if len(files) != 30 || files[0].Version != "000001" || files[1].Version != "000002" || files[2].Version != "000003" || files[3].Version != "000004" || files[4].Version != "000005" || files[5].Version != "000006" || files[6].Version != "000007" || files[7].Version != "000008" || files[8].Version != "000009" || files[9].Version != "000010" || files[10].Version != "000011" || files[11].Version != "000012" || files[12].Version != "000013" || files[13].Version != "000014" || files[14].Version != "000015" || files[15].Version != "000016" || files[16].Version != "000017" || files[17].Version != "000018" || files[18].Version != "000019" || files[19].Version != "000020" || files[20].Version != "000021" || files[21].Version != "000022" || files[22].Version != "000023" || files[23].Version != "000024" || files[24].Version != "000025" || files[25].Version != "000026" || files[26].Version != "000027" || files[27].Version != "000028" || files[28].Version != "000029" || files[29].Version != "000030" {
		t.Fatalf("unexpected migration order: %#v", files)
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
	for _, table := range []string{"users", "user_profiles", "community_categories", "communities", "posts", "user_auth_methods", "sessions", "refresh_tokens", "post_revisions", "post_idempotency_keys", "media_assets", "post_media", "comments", "comment_idempotency_keys", "post_reactions", "comment_reactions", "bookmarks", "bookmark_folders", "bookmark_folder_items", "user_follows", "community_follows", "community_members", "notifications", "reports", "moderation_cases", "moderation_actions", "roles", "permissions", "role_permissions", "user_roles", "audit_logs", "blocks", "outbox_events", "point_transactions", "polls", "poll_options", "poll_votes", "market_items", "user_post_histories", "store_products", "store_orders", "moderation_appeals", "moderation_appeal_media", "ranking_toys", "ranking_toy_user_states", "ranking_toy_rating_distribution", "ranking_toy_comments", "ranking_toy_comment_likes", "email_codes", "guest_sessions", "bans", "restrictions", "admin_invites", "login_devices", "risk_events", "admin_log_chain", "admin_logs", "ip_restrictions", "home_recommendations"} {
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
