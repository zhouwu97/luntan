package api

import (
	"testing"
	"time"
)

func TestSearchCursorRoundTripAndKindBinding(t *testing.T) {
	original := searchCursor{
		Kind:      "posts",
		Rank:      0.75,
		CreatedAt: time.Date(2026, 8, 24, 10, 0, 0, 0, time.UTC),
		ID:        "post-1",
	}
	encoded, err := encodeSearchCursor(original)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := decodeSearchCursor(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if decoded.Kind != original.Kind || decoded.ID != original.ID || decoded.Rank != original.Rank || !decoded.CreatedAt.Equal(original.CreatedAt) {
		t.Fatalf("decoded cursor = %#v, want %#v", decoded, original)
	}
	if _, err := decodeSearchCursor("not-a-cursor"); err == nil {
		t.Fatal("invalid search cursor should be rejected")
	}
}
