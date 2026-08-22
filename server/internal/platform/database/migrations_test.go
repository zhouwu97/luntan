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
	if len(files) != 4 || files[0].Version != "000001" || files[1].Version != "000002" || files[2].Version != "000003" || files[3].Version != "000004" {
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
	for _, table := range []string{"users", "user_profiles", "community_categories", "communities", "posts", "user_auth_methods", "sessions", "refresh_tokens"} {
		var exists bool
		if err := db.QueryRowContext(ctx, `SELECT to_regclass($1) IS NOT NULL`, "public."+table).Scan(&exists); err != nil {
			t.Fatal(err)
		}
		if !exists {
			t.Fatalf("table %s does not exist", table)
		}
	}
}
