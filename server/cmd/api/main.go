package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/zhouwu97/luntan/server/internal/api"
	"github.com/zhouwu97/luntan/server/internal/platform/config"
	"github.com/zhouwu97/luntan/server/internal/platform/database"
	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
	"github.com/zhouwu97/luntan/server/internal/platform/logging"
)

func main() {
	cfg := config.Load()
	logger := logging.New(cfg.LogLevel)
	db, err := database.Open(cfg.DatabaseURL)
	if err != nil {
		logger.Error("database_open_failed", "error", err.Error())
		os.Exit(1)
	}
	if db != nil {
		defer db.Close()
		migrationDir := filepath.Join("server", "migrations")
		if _, statErr := os.Stat(migrationDir); errors.Is(statErr, os.ErrNotExist) {
			migrationDir = "migrations"
		}
		if err := database.Migrate(context.Background(), db, migrationDir); err != nil {
			logger.Error("database_migration_failed", "error", err.Error())
			os.Exit(1)
		}
	}

	server := &http.Server{Addr: fmt.Sprintf(":%s", cfg.HTTPPort), Handler: httpserver.NewHandlerWithAPI(db, logger, api.NewHandler(db)), ReadHeaderTimeout: 5 * time.Second}
	go func() {
		logger.Info("http_server_started", "app_env", cfg.AppEnv, "port", cfg.HTTPPort)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("http_server_failed", "error", err.Error())
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		logger.Error("http_server_shutdown_failed", "error", err.Error())
	}
}
