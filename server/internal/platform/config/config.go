package config

import "os"

type Config struct {
	AppEnv                     string
	HTTPPort                   string
	DatabaseURL                string
	LogLevel                   string
	RedisURL                   string
	ObjectStorageUploadBaseURL string
	ObjectStorageSigningSecret string
	RateLimitEnabled           bool
}

func Load() Config {
	return Config{
		AppEnv:                     valueOrDefault("APP_ENV", "dev"),
		HTTPPort:                   valueOrDefault("HTTP_PORT", "8080"),
		DatabaseURL:                os.Getenv("DATABASE_URL"),
		LogLevel:                   valueOrDefault("LOG_LEVEL", "info"),
		RedisURL:                   os.Getenv("REDIS_URL"),
		ObjectStorageUploadBaseURL: os.Getenv("OBJECT_STORAGE_UPLOAD_BASE_URL"),
		ObjectStorageSigningSecret: os.Getenv("OBJECT_STORAGE_SIGNING_SECRET"),
		RateLimitEnabled:           valueOrDefault("RATE_LIMIT_ENABLED", "false") == "true",
	}
}

func valueOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
