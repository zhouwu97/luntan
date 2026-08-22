package database

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type MigrationFile struct {
	Version string
	Path    string
}

func ListUpMigrations(directory string) ([]MigrationFile, error) {
	entries, err := os.ReadDir(directory)
	if err != nil {
		return nil, fmt.Errorf("read migrations directory: %w", err)
	}
	files := make([]MigrationFile, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".up.sql") {
			continue
		}
		parts := strings.SplitN(entry.Name(), "_", 2)
		if len(parts) != 2 || parts[0] == "" {
			return nil, fmt.Errorf("invalid migration filename: %s", entry.Name())
		}
		files = append(files, MigrationFile{Version: parts[0], Path: filepath.Join(directory, entry.Name())})
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Version < files[j].Version })
	return files, nil
}

func Migrate(ctx context.Context, db *sql.DB, directory string) error {
	if db == nil {
		return fmt.Errorf("migrate database: database is not configured")
	}
	files, err := ListUpMigrations(directory)
	if err != nil {
		return err
	}
	if _, err := db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version text PRIMARY KEY,
		applied_at timestamptz NOT NULL DEFAULT now()
	)`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	for _, migration := range files {
		var applied bool
		if err := db.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`, migration.Version).Scan(&applied); err != nil {
			return fmt.Errorf("check migration %s: %w", migration.Version, err)
		}
		if applied {
			continue
		}
		sqlBytes, err := os.ReadFile(migration.Path)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", migration.Version, err)
		}
		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return fmt.Errorf("begin migration %s: %w", migration.Version, err)
		}
		if _, err = tx.ExecContext(ctx, string(sqlBytes)); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("apply migration %s: %w", migration.Version, err)
		}
		if _, err = tx.ExecContext(ctx, `INSERT INTO schema_migrations (version) VALUES ($1)`, migration.Version); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("record migration %s: %w", migration.Version, err)
		}
		if err = tx.Commit(); err != nil {
			return fmt.Errorf("commit migration %s: %w", migration.Version, err)
		}
	}
	return nil
}
