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
func TestValidateProduction(t *testing.T) {
	cfg := Config{
		AppEnv: "production",
	}
	if err := cfg.Validate(); err == nil {
		t.Fatalf("expected error for empty production config")
	}

	cfg.DatabaseURL = "postgres://localhost/db"
	cfg.ObjectStorageUploadBaseURL = "https://upload.example.com"
	cfg.ObjectStorageSigningSecret = "secret"
	if err := cfg.Validate(); err == nil {
		t.Fatalf("expected error for missing ObjectStoragePublicBaseURL")
	}

	cfg.ObjectStoragePublicBaseURL = "https://cdn.example.com"
	if err := cfg.Validate(); err != nil {
		t.Fatalf("expected valid production config, got: %v", err)
	}
}
