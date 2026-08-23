package api

import (
	"testing"
	"time"
)

func TestFeedCursorRoundTrip(t *testing.T) {
	original := feedCursor{PublishedAt: time.Date(2026, 8, 22, 12, 0, 0, 123, time.UTC), ID: "post-2"}
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

func TestFeedCursorRejectsInvalidValue(t *testing.T) {
	if _, err := decodeFeedCursor("not-a-cursor"); err == nil {
		t.Fatal("invalid cursor was accepted")
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
