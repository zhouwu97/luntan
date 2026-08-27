package api

import "testing"

func TestParseFeedFilters(t *testing.T) {
	filter, err := parseFeedFilter("game_share", "true")
	if err != nil {
		t.Fatal(err)
	}
	if filter.PostType != "game_share" || !filter.HasMedia {
		t.Fatalf("unexpected filter: %#v", filter)
	}
	filter, err = parseFeedFilter("", "", "outfit")
	if err != nil || filter.Topic != "outfit" {
		t.Fatalf("topic filter not parsed: %#v, %v", filter, err)
	}
	if _, err := parseFeedFilter("unknown", "true"); err == nil {
		t.Fatal("unknown post type should be rejected")
	}
	if _, err := parseFeedFilter("normal", "maybe"); err == nil {
		t.Fatal("invalid has_media should be rejected")
	}
	if _, err := parseFeedFilter("", "", "unknown"); err == nil {
		t.Fatal("invalid topic should be rejected")
	}
}
