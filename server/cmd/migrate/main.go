package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/zhouwu97/luntan/server/internal/platform/config"
	"github.com/zhouwu97/luntan/server/internal/platform/database"
)

func main() {
	cfg := config.Load()
	db, err := database.Open(cfg.DatabaseURL)
	if err != nil {
		fail(err)
	}
	if db == nil {
		fail(errors.New("DATABASE_URL 未配置"))
	}
	defer db.Close()

	migrationDir := filepath.Join("server", "migrations")
	if _, statErr := os.Stat(migrationDir); errors.Is(statErr, os.ErrNotExist) {
		migrationDir = "migrations"
	}
	if err := database.Migrate(context.Background(), db, migrationDir); err != nil {
		fail(err)
	}
	fmt.Println("database migrations applied")
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
