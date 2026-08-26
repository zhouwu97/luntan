package api

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"
)

type feedCursor struct {
	PublishedAt   time.Time  `json:"published_at,omitempty"`
	ActivityAt    *time.Time `json:"activity_at,omitempty"`
	Position      *int       `json:"position,omitempty"`
	RecommendedAt *time.Time `json:"recommended_at,omitempty"`
	ID            string     `json:"id"`
	// Score 只在基于评分的排序（hot/featured）中出现，
	// latest/recommended 排序的游标不含该字段。
	Score *float64 `json:"score,omitempty"`
	// AsOf 固定评分所使用的时间，避免跨页请求之间 now() 漂移导致上一页最后一条再次出现。
	AsOf *time.Time `json:"as_of,omitempty"`
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
	if err := json.Unmarshal(data, &cursor); err != nil || cursor.ID == "" {
		return feedCursor{}, fmt.Errorf("invalid cursor")
	}
	if cursor.PublishedAt.IsZero() && cursor.ActivityAt == nil && cursor.Position == nil {
		return feedCursor{}, fmt.Errorf("invalid cursor")
	}
	return cursor, nil
}

