package main

import (
	"context"
	"errors"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/zhouwu97/luntan/server/internal/outbox"
	"github.com/zhouwu97/luntan/server/internal/platform/config"
	"github.com/zhouwu97/luntan/server/internal/platform/database"
	"github.com/zhouwu97/luntan/server/internal/platform/logging"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

func main() {
	cfg := config.Load()
	logger := logging.New(cfg.LogLevel)
	db, err := database.Open(cfg.DatabaseURL)
	if err != nil || db == nil {
		if err == nil {
			err = errors.New("database is not configured")
		}
		logger.Error("worker_database_open_failed", "error", err.Error())
		os.Exit(1)
	}
	defer db.Close()
	router := outbox.NewRouterHandler()
	router.Register("notification.created", outbox.NotificationHandler{
		DB:         db,
		WebhookURL: os.Getenv("PUSH_WEBHOOK_URL"),
		Secret:     os.Getenv("PUSH_WEBHOOK_SECRET"),
	})
	objStorage := storage.NewObjectStorageFromEnv()
	mediaHandler := outbox.MediaHandler{
		DB:      db,
		Storage: objStorage,
	}
	router.Register("media.process", mediaHandler)
	router.Register("media.delete", mediaHandler)

	worker := outbox.Worker{
		DB:          db,
		Handler:     router,
		BatchSize:   50,
		MaxAttempts: 8,
	}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		if _, err := worker.RunOnce(ctx); err != nil {
			logger.Error("outbox_run_failed", "error", err.Error())
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
