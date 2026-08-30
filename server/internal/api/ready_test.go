package api

import (
	"context"
	"errors"
	"testing"

	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

type failingHealthStorage struct {
	*storage.MemoryStorage
}

func (failingHealthStorage) HealthCheck(context.Context) error {
	return errors.New("object storage unreachable")
}

func TestReadyProbesConfiguredStorage(t *testing.T) {
	server := &Server{mediaStorage: storage.NewMemoryStorage(), appEnv: "production"}
	if err := server.Ready(context.Background()); err != nil {
		t.Fatalf("memory storage should be ready: %v", err)
	}

	broken := &Server{mediaStorage: failingHealthStorage{storage.NewMemoryStorage()}, appEnv: "production"}
	if err := broken.Ready(context.Background()); err == nil {
		t.Fatal("ready 必须暴露探测失败的存储，而不是只检查配置存在")
	}
}

func TestReadyUnavailableStorage(t *testing.T) {
	production := &Server{mediaStorage: unavailableMediaStorage{}, appEnv: "production"}
	if err := production.Ready(context.Background()); !errors.Is(err, ErrStorageUnavailable) {
		t.Fatalf("expected ErrStorageUnavailable, got %v", err)
	}

	development := &Server{mediaStorage: unavailableMediaStorage{}, appEnv: "dev"}
	if err := development.Ready(context.Background()); err != nil {
		t.Fatalf("dev 环境允许无存储启动，got %v", err)
	}
}
