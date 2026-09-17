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
		cursorSort   string
		requestQuery string
	}{
		{cursorSort: "recommended", requestQuery: "sort=hot"},
		{cursorSort: "hot", requestQuery: "sort=featured"},
		{cursorSort: "featured", requestQuery: "sort=recommended"},
		{cursorSort: "latest:comment", requestQuery: "sort=latest&latest_by=post"},
		{cursorSort: "latest:post", requestQuery: "sort=latest&latest_by=comment"},
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
		req := httptest.NewRequest(http.MethodGet, "/api/v1/feed/latest?"+tt.requestQuery+"&cursor="+url.QueryEscape(cursor), nil)
		rec := httptest.NewRecorder()
		(&Server{db: db}).latestFeed(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s cursor 用于 %s 应返回 400，实际 %d：%s", tt.cursorSort, tt.requestQuery, rec.Code, rec.Body.String())
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

func TestFeedCursorRoundTripWithRevision(t *testing.T) {
	asOf := time.Now().UTC()
	rev := feedRankingEpoch(asOf)
	score := 50.0
	pinned := false
	original := feedCursor{
		Sort:                 "recommended",
		Score:                &score,
		RecommendationPinned: &pinned,
		PublishedAt:          asOf,
		AsOf:                 &asOf,
		Revision:             rev,
		ID:                   "post-rev",
	}
	encoded, err := encodeFeedCursor(original)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := decodeFeedCursor(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if decoded.Revision != rev {
		t.Fatalf("revision changed after round trip: got %d, want %d", decoded.Revision, rev)
	}
}

func TestFeedRankingEpoch(t *testing.T) {
	t1 := time.Date(2026, 9, 17, 8, 0, 10, 0, time.UTC)
	t2 := time.Date(2026, 9, 17, 8, 0, 25, 0, time.UTC)
	t3 := time.Date(2026, 9, 17, 8, 0, 35, 0, time.UTC)

	// t1 and t2 fall into the same 30s bucket (0~29s)
	if feedRankingEpoch(t1) != feedRankingEpoch(t2) {
		t.Fatalf("t1 and t2 should share the same 30s epoch: %d vs %d", feedRankingEpoch(t1), feedRankingEpoch(t2))
	}
	// t3 falls into the next 30s bucket (30~59s)
	if feedRankingEpoch(t3) <= feedRankingEpoch(t1) {
		t.Fatalf("t3 should be in next epoch: %d <= %d", feedRankingEpoch(t3), feedRankingEpoch(t1))
	}
}

func TestFeedCursorRejectsStaleEpoch(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// 构造 45 秒前的游标（超出 30 秒 coarse epoch 窗口）
	staleAsOf := time.Now().UTC().Add(-45 * time.Second)
	score := 33.0
	pinned := false
	staleCursor, err := encodeFeedCursor(feedCursor{
		Sort:                 "recommended",
		Score:                &score,
		RecommendationPinned: &pinned,
		PublishedAt:          staleAsOf,
		AsOf:                 &staleAsOf,
		Revision:             feedRankingEpoch(staleAsOf),
		ID:                   "post-stale",
	})
	if err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/feed/latest?sort=recommended&cursor="+url.QueryEscape(staleCursor), nil)
	rec := httptest.NewRecorder()
	(&Server{db: db}).latestFeed(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("过期 epoch 游标应返回 400，实际 %d：%s", rec.Code, rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

