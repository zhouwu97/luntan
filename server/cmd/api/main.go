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
	"github.com/zhouwu97/luntan/server/internal/platform/mail"
)

func main() {
	cfg := config.Load()
	logger := logging.New(cfg.LogLevel)
	if _, err := mail.NewSender(mail.ConfigFromEnv(cfg.AppEnv)); err != nil {
		logger.Error("mail_configuration_failed", "error", err.Error())
		os.Exit(1)
	}
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
	var rateLimitStore httpserver.RateLimitStore
	if cfg.RateLimitEnabled {
		if cfg.RedisURL == "" {
			if cfg.AppEnv == "production" {
				logger.Error("rate_limit_store_missing", "error", "production requires REDIS_URL")
				os.Exit(1)
			}
			logger.Warn("rate_limit_memory_store", "app_env", cfg.AppEnv)
			rateLimitStore = httpserver.NewMemoryRateLimitStore()
		} else {
			redisStore, redisErr := httpserver.NewRedisRateLimitStore(cfg.RedisURL)
			if redisErr != nil {
				logger.Error("rate_limit_redis_failed", "error", redisErr.Error())
				os.Exit(1)
			}
			defer redisStore.Close()
			rateLimitStore = redisStore
		}
	}
	sender, senderErr := mail.NewSender(mail.ConfigFromEnv(cfg.AppEnv))
	if senderErr != nil {
		logger.Error("mail_sender_failed", "error", senderErr.Error())
		os.Exit(1)
	}
	handler, err := httpserver.NewHandlerWithAPIOptions(db, logger, api.NewHandlerWithMail(db, sender, cfg.AppEnv), httpserver.Options{
		RateLimitEnabled:  cfg.RateLimitEnabled,
		RateLimitStore:    rateLimitStore,
		TrustedProxyCIDRs: cfg.TrustedProxyCIDRs,
	})
	if err != nil {
		logger.Error("http_server_configuration_failed", "error", err.Error())
		os.Exit(1)
	}

	server := &http.Server{
		Addr:              fmt.Sprintf(":%s", cfg.HTTPPort),
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}
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
