package config

import "testing"

func TestLoadDefaults(t *testing.T) {
	t.Setenv("APP_ENV", "")
	t.Setenv("HTTP_PORT", "")
	t.Setenv("DATABASE_URL", "")
	t.Setenv("LOG_LEVEL", "")
	cfg := Load()
	if cfg.AppEnv != "dev" || cfg.HTTPPort != "8080" || cfg.LogLevel != "info" {
		t.Fatalf("unexpected defaults: %#v", cfg)
	}
}
