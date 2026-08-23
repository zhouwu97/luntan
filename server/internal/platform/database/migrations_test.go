package database

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMigrationFilesAreOrderedAndPaired(t *testing.T) {
	directory := filepath.Join("..", "..", "..", "migrations")
	files, err := ListUpMigrations(directory)
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 16 || files[0].Version != "000001" || files[1].Version != "000002" || files[2].Version != "000003" || files[3].Version != "000004" || files[4].Version != "000005" || files[5].Version != "000006" || files[6].Version != "000007" || files[7].Version != "000008" || files[8].Version != "000009" || files[9].Version != "000010" || files[10].Version != "000011" || files[11].Version != "000012" || files[12].Version != "000013" || files[13].Version != "000014" || files[14].Version != "000015" || files[15].Version != "000016" {
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
	for _, table := range []string{"users", "user_profiles", "community_categories", "communities", "posts", "user_auth_methods", "sessions", "refresh_tokens", "post_revisions", "post_idempotency_keys", "media_assets", "post_media", "comments", "post_reactions", "comment_reactions", "bookmarks", "user_follows", "community_follows", "community_members", "notifications", "reports", "moderation_cases", "moderation_actions", "roles", "permissions", "role_permissions", "user_roles", "audit_logs", "blocks", "outbox_events", "point_transactions", "polls", "poll_options", "poll_votes", "market_items", "user_post_histories", "store_products", "store_orders"} {
		var exists bool
		if err := db.QueryRowContext(ctx, `SELECT to_regclass($1) IS NOT NULL`, "public."+table).Scan(&exists); err != nil {
			t.Fatal(err)
		}
		if !exists {
			t.Fatalf("table %s does not exist", table)
		}
	}
}
