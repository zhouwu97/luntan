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
	email := flag.String("email", "", "已存在的正式邮箱账号")
	reason := flag.String("reason", "交付验收请求授予超级管理员", "审计原因")
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
	created, err := api.GrantSuperAdmin(ctx, db, *email, *reason)
	if err != nil {
		fail(err)
	}
	if created {
		fmt.Println("super admin granted")
	} else {
		fmt.Println("super admin already granted; no changes made")
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
