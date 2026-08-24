package api

import (
	"testing"
	"time"
)

func TestNotificationCategoryValidation(t *testing.T) {
	for _, value := range []string{"", "all", "reply", "like", "system"} {
		category, err := parseNotificationCategory(value)
		if err != nil {
			t.Fatalf("parseNotificationCategory(%q): %v", value, err)
		}
		if value == "" && category != "all" {
			t.Fatalf("empty category = %q, want all", category)
		}
	}
	if _, err := parseNotificationCategory("unknown"); err == nil {
		t.Fatal("unknown category should be rejected")
	}
}

func TestNotificationCursorIsBoundToCategory(t *testing.T) {
	encoded, err := encodeNotificationCursor(notificationCursor{
		CreatedAt: time.Date(2026, 8, 24, 10, 0, 0, 0, time.UTC),
		ID:        "notification-1",
		Category:  "reply",
	})
	if err != nil {
		t.Fatal(err)
	}
	cursor, err := decodeNotificationCursor(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if cursor.Category != "reply" {
		t.Fatalf("cursor category = %q, want reply", cursor.Category)
	}
	if cursor.Category == "like" {
		t.Fatal("reply cursor must not be reusable for like category")
	}
}
