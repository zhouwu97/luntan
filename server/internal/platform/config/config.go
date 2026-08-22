package config

import "os"

type Config struct {
	AppEnv      string
	HTTPPort    string
	DatabaseURL string
	LogLevel    string
}

func Load() Config {
	return Config{
		AppEnv:      valueOrDefault("APP_ENV", "dev"),
		HTTPPort:    valueOrDefault("HTTP_PORT", "8080"),
		DatabaseURL: os.Getenv("DATABASE_URL"),
		LogLevel:    valueOrDefault("LOG_LEVEL", "info"),
	}
}

func valueOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
