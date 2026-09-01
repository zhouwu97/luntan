package api

import (
	"testing"
	"time"
)

func TestStoreRewardContentCursorRoundTrip(t *testing.T) {
	original := storeRewardContentCursor{
		Priority: 2,
		EarnedAt: time.Date(2026, 8, 31, 12, 0, 0, 123, time.UTC),
		ID:       "tx-2",
	}
	encoded, err := encodeStoreRewardContentCursor(original)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := decodeStoreRewardContentCursor(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if decoded.Priority != original.Priority ||
		!decoded.EarnedAt.Equal(original.EarnedAt) || decoded.ID != original.ID {
		t.Fatalf("cursor changed after round trip: %#v", decoded)
	}
}

func TestStoreRewardContentCursorRejectsInvalidValue(t *testing.T) {
	for _, value := range []string{"not-a-cursor", "eyJpZCI6IiJ9"} {
		if _, err := decodeStoreRewardContentCursor(value); err == nil {
			t.Fatalf("invalid cursor %q was accepted", value)
		}
	}
}

func TestRewardContentPriorityPutsUnavailableAndEditedFirst(t *testing.T) {
	cases := []struct {
		status string
		edited bool
		want   int
	}{
		{status: "deleted", want: 2},
		{status: "unavailable", edited: true, want: 2},
		{status: "normal", edited: true, want: 1},
		{status: "normal", want: 0},
	}
	for _, tc := range cases {
		if got := rewardContentPriority(tc.status, tc.edited); got != tc.want {
			t.Errorf("priority(%q, %t) = %d, want %d", tc.status, tc.edited, got, tc.want)
		}
	}
}
