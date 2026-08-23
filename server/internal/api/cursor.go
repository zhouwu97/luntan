package api

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"
)

type feedCursor struct {
	PublishedAt time.Time `json:"published_at"`
	ID          string    `json:"id"`
	// Score 只在基于评分的排序（recommended/hot/featured）中出现，
	// latest 排序的游标不含该字段。
	Score *float64 `json:"score,omitempty"`
}

func encodeFeedCursor(cursor feedCursor) (string, error) {
	data, err := json.Marshal(cursor)
	if err != nil {
		return "", fmt.Errorf("encode cursor: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func decodeFeedCursor(value string) (feedCursor, error) {
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return feedCursor{}, fmt.Errorf("decode cursor: %w", err)
	}
	var cursor feedCursor
	if err := json.Unmarshal(data, &cursor); err != nil || cursor.ID == "" || cursor.PublishedAt.IsZero() {
		return feedCursor{}, fmt.Errorf("invalid cursor")
	}
	return cursor, nil
}
