package config

import "testing"

func TestLoadDefaults(t *testing.T) {
	t.Setenv("APP_ENV", "")
	t.Setenv("HTTP_PORT", "")
	t.Setenv("DATABASE_URL", "")
	t.Setenv("LOG_LEVEL", "")
	cfg := Load()
	if cfg.AppEnv != "" || cfg.HTTPPort != "8080" || cfg.LogLevel != "info" {
		t.Fatalf("unexpected defaults: %#v", cfg)
	}
}

func TestValidateRejectsUnknownEnvironment(t *testing.T) {
	for _, appEnv := range []string{"", "prod", "prd", "production-like"} {
		if err := (Config{AppEnv: appEnv}).Validate(); err == nil {
			t.Fatalf("APP_ENV=%q should be rejected", appEnv)
		}
	}
}

func TestValidateRejectsDevelopmentAuthCodeOutsideDevelopment(t *testing.T) {
	if err := (Config{AppEnv: "production", AllowDevAuthCode: true}).Validate(); err == nil {
		t.Fatal("production must reject ALLOW_DEV_AUTH_CODE=true")
	}
	if err := (Config{AppEnv: "staging", AllowDevAuthCode: true}).Validate(); err == nil {
		t.Fatal("staging must reject ALLOW_DEV_AUTH_CODE=true")
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
	if err := cfg.Validate(); err == nil || err.Error() != "production requires RATE_LIMIT_ENABLED=true" {
		t.Fatalf("expected rate limit error, got: %v", err)
	}

	cfg.RateLimitEnabled = true
	if err := cfg.Validate(); err == nil || err.Error() != "production requires REDIS_URL to back the rate limiter" {
		t.Fatalf("expected redis error, got: %v", err)
	}

	cfg.RedisURL = "redis://localhost:6379/0"
	cfg.AuthCodeHashSecret = "01234567890123456789012345678901"
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

func TestValidateProductionRejectsPlainTextClientFacingURLs(t *testing.T) {
	base := Config{
		AppEnv:                     "production",
		DatabaseURL:                "postgres://localhost/db",
		RateLimitEnabled:           true,
		RedisURL:                   "redis://localhost:6379/0",
		AuthCodeHashSecret:         "01234567890123456789012345678901",
		ObjectStorageUploadBaseURL: "https://upload.example.com",
		ObjectStorageSigningSecret: "secret",
		ObjectStoragePublicBaseURL: "https://cdn.example.com",
	}

	cases := []struct {
		name    string
		mutate  func(c *Config)
		wantErr string
	}{
		{
			name:    "upload base url over http",
			mutate:  func(c *Config) { c.ObjectStorageUploadBaseURL = "http://upload.example.com" },
			wantErr: "OBJECT_STORAGE_UPLOAD_BASE_URL must use HTTPS in production",
		},
		{
			name:    "public base url over http",
			mutate:  func(c *Config) { c.ObjectStoragePublicBaseURL = "http://cdn.example.com" },
			wantErr: "OBJECT_STORAGE_PUBLIC_BASE_URL must use HTTPS in production",
		},
		{
			name:    "app release base url over http",
			mutate:  func(c *Config) { c.AppReleasePublicBaseURL = "http://download.example.com" },
			wantErr: "APP_RELEASE_PUBLIC_BASE_URL must use HTTPS in production",
		},
		{
			name:    "app release download base url over http",
			mutate:  func(c *Config) { c.AppReleaseDownloadBaseURL = "http://cdn.example.com" },
			wantErr: "APP_RELEASE_DOWNLOAD_BASE_URL must use HTTPS in production",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			cfg := base
			tc.mutate(&cfg)
			err := cfg.Validate()
			if err == nil || err.Error() != tc.wantErr {
				t.Fatalf("expected %q, got: %v", tc.wantErr, err)
			}
		})
	}
}

func TestValidateProductionAllowsInternalStorageHTTP(t *testing.T) {
	t.Setenv("STORAGE_INTERNAL_BASE_URL", "http://storage.internal:9000")
	cfg := Config{
		AppEnv:                     "production",
		DatabaseURL:                "postgres://localhost/db",
		RateLimitEnabled:           true,
		RedisURL:                   "redis://localhost:6379/0",
		AuthCodeHashSecret:         "01234567890123456789012345678901",
		ObjectStorageUploadBaseURL: "https://upload.example.com",
		ObjectStorageSigningSecret: "secret",
		ObjectStoragePublicBaseURL: "https://cdn.example.com",
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("internal server-to-server storage URL should keep HTTP, got: %v", err)
	}
}

func TestValidateNonProductionKeepsFlexibleStorageScheme(t *testing.T) {
	t.Setenv("STORAGE_INTERNAL_BASE_URL", "http://storage.internal:9000")
	cfg := Config{
		AppEnv:                     "qa",
		ObjectStorageUploadBaseURL: "http://upload.example.com",
		ObjectStoragePublicBaseURL: "http://cdn.example.com",
	}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("QA/dev 允许 HTTP 存储，got: %v", err)
	}
}
