package logging

import (
	"log/slog"
	"os"
	"strings"
)

func New(level string) *slog.Logger {
	var minLevel slog.Level
	switch strings.ToLower(level) {
	case "debug":
		minLevel = slog.LevelDebug
	case "warn", "warning":
		minLevel = slog.LevelWarn
	case "error":
		minLevel = slog.LevelError
	default:
		minLevel = slog.LevelInfo
	}

	options := &slog.HandlerOptions{Level: minLevel}
	return slog.New(slog.NewJSONHandler(os.Stdout, options))
}
