package api

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestFeedCursorRoundTrip(t *testing.T) {
	original := feedCursor{Sort: "latest:post", PublishedAt: time.Date(2026, 8, 22, 12, 0, 0, 123, time.UTC), ID: "post-2"}
	encoded, err := encodeFeedCursor(original)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := decodeFeedCursor(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if !decoded.PublishedAt.Equal(original.PublishedAt) || decoded.ID != original.ID {
		t.Fatalf("cursor changed after round trip: %#v", decoded)
	}
}

func TestFeedCursorRoundTripWithScore(t *testing.T) {
	score := 42.5
	original := feedCursor{
		Sort:        "hot",
		PublishedAt: time.Date(2026, 8, 22, 12, 0, 0, 123, time.UTC),
		ID:          "post-2",
		Score:       &score,
	}
	encoded, err := encodeFeedCursor(original)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := decodeFeedCursor(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if decoded.Score == nil || *decoded.Score != score {
		t.Fatalf("score changed after round trip: %#v", decoded.Score)
	}
}

func TestFeedCursorRoundTripWithAsOf(t *testing.T) {
	asOf := time.Date(2026, 8, 26, 12, 0, 0, 123, time.UTC)
	activity := time.Date(2026, 8, 26, 11, 59, 0, 0, time.UTC)
	original := feedCursor{
		Sort:       "latest:comment",
		ActivityAt: &activity,
		AsOf:       &asOf,
		ID:         "post-2",
	}
	encoded, err := encodeFeedCursor(original)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := decodeFeedCursor(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if decoded.AsOf == nil || !decoded.AsOf.Equal(asOf) {
		t.Fatalf("as_of changed after round trip: %#v", decoded.AsOf)
	}
}

func TestRecommendedFeedCursorRoundTripWithPinState(t *testing.T) {
	pinned := true
	position := 3
	recommendedAt := time.Date(2026, 9, 8, 8, 0, 0, 0, time.UTC)
	asOf := time.Date(2026, 9, 8, 9, 0, 0, 0, time.UTC)
	original := feedCursor{
		Sort:                 "recommended",
		RecommendationPinned: &pinned,
		Position:             &position,
		RecommendedAt:        &recommendedAt,
		AsOf:                 &asOf,
		ID:                   "post-pinned",
	}

	encoded, err := encodeFeedCursor(original)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := decodeFeedCursor(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if decoded.RecommendationPinned == nil || !*decoded.RecommendationPinned {
		t.Fatalf("recommendation pin state changed after round trip: %#v", decoded.RecommendationPinned)
	}
}

func TestFeedCursorRejectsInvalidValue(t *testing.T) {
	if _, err := decodeFeedCursor("not-a-cursor"); err == nil {
		t.Fatal("invalid cursor was accepted")
	}
}

func TestFeedCursorRejectsCrossSortReuse(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	score := 12.5
	asOf := time.Date(2026, 9, 9, 12, 0, 0, 0, time.UTC)
	publishedAt := asOf.Add(-time.Hour)
	tests := []struct {
		cursorSort  string
		requestSort string
	}{
		{cursorSort: "recommended", requestSort: "hot"},
		{cursorSort: "hot", requestSort: "featured"},
		{cursorSort: "featured", requestSort: "recommended"},
	}
	for _, tt := range tests {
		cursor, err := encodeFeedCursor(feedCursor{
			Sort:        tt.cursorSort,
			PublishedAt: publishedAt,
			Score:       &score,
			AsOf:        &asOf,
			ID:          "post-1",
		})
		if err != nil {
			t.Fatal(err)
		}
		req := httptest.NewRequest(http.MethodGet, "/api/v1/feed/latest?sort="+tt.requestSort+"&cursor="+url.QueryEscape(cursor), nil)
		rec := httptest.NewRecorder()
		(&Server{db: db}).latestFeed(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s cursor 用于 %s 应返回 400，实际 %d：%s", tt.cursorSort, tt.requestSort, rec.Code, rec.Body.String())
		}
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestParseLimit(t *testing.T) {
	if limit, err := parseLimit(""); err != nil || limit != 20 {
		t.Fatalf("default limit = %d, err = %v", limit, err)
	}
	if _, err := parseLimit("0"); err == nil {
		t.Fatal("zero limit was accepted")
	}
	if _, err := parseLimit("51"); err == nil {
		t.Fatal("limit over 50 was accepted")
	}
}
