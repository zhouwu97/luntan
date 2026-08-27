package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/zhouwu97/luntan/server/internal/api"
	"github.com/zhouwu97/luntan/server/internal/platform/config"
	"github.com/zhouwu97/luntan/server/internal/platform/database"
)

func main() {
	email := flag.String("email", os.Getenv("BOOTSTRAP_SUPER_ADMIN_EMAIL"), "已存在的超级管理员邮箱")
	flag.Parse()
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
	ctx := context.Background()
	if err := database.Migrate(ctx, db, migrationDir); err != nil {
		fail(err)
	}
	created, err := api.BootstrapSuperAdmin(ctx, db, *email)
	if err != nil {
		fail(err)
	}
	if created {
		fmt.Println("super admin bootstrapped")
	} else {
		fmt.Println("super admin already exists; no changes made")
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
