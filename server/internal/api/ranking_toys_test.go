package api

import (
	"database/sql"
	"testing"
	"time"
)

func TestRankingToyScoreUsesCentiUnits(t *testing.T) {
	tests := []struct {
		name       string
		totalCenti int64
		count      int64
		want       float64
	}{
		{name: "8.7", totalCenti: 14790, count: 17, want: 8.7},
		{name: "9.1", totalCenti: 81900, count: 90, want: 9.1},
		{name: "round half up", totalCenti: 17730, count: 20, want: 8.9},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			item := rankingToyRecord{RatingTotalCenti: tt.totalCenti, RatingCount: tt.count}
			if got := item.score(); got != tt.want {
				t.Fatalf("score() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestRankingToyRecordResponseIncludesCategoryAndSegments(t *testing.T) {
	item := rankingToyRecord{
		ID:               "toy-butter-2",
		Rank:             1,
		Name:             "黄油小姐 二代",
		Category:         "cup",
		Segments:         []string{"beginner"},
		RatingTotalCenti: 870,
		RatingCount:      1,
	}
	resp := item.response()
	if resp["category"] != "cup" {
		t.Fatalf("resp[category] = %v, want 'cup'", resp["category"])
	}
	segments, ok := resp["segments"].([]string)
	if !ok || len(segments) != 1 || segments[0] != "beginner" {
		t.Fatalf("resp[segments] = %#v, want ['beginner']", resp["segments"])
	}
}

func TestRankingToyCommentResponseIncludesAuthorRatingAndLevel(t *testing.T) {
	comment := rankingToyComment{
		ID:           "c-1",
		AuthorID:     "u-1",
		Username:     "tester",
		Nickname:     "Tester Nick",
		Level:        4,
		Content:      "非常好",
		CreatedAt:    time.Now(),
		AuthorRating: sql.NullInt64{Int64: 9, Valid: true},
	}
	resp := comment.response()
	if resp["author_rating"] != int64(9) {
		t.Fatalf("resp[author_rating] = %v, want 9", resp["author_rating"])
	}
	author, ok := resp["author"].(map[string]any)
	if !ok || author["level"] != 4 || author["author_rating"] != int64(9) {
		t.Fatalf("author map = %#v, want level=4, author_rating=9", author)
	}
}

