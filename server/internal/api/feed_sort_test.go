package api

import (
	"strings"
	"testing"
)

func TestFeedSortColumns(t *testing.T) {
	tests := []struct {
		sort      string
		scored    bool
		wantOrder string
		wantExpr  string
	}{
		{"latest", false, "ORDER BY p.published_at DESC, p.id DESC", ""},
		{"featured", true, "ORDER BY", "bookmark_count"},
		{"recommended", true, "ORDER BY", "unique_commenters"},
		{"hot", true, "ORDER BY", "POWER"},
		{"unknown-sort", false, "ORDER BY p.published_at DESC, p.id DESC", ""},
	}
	for _, tt := range tests {
		scoreExpr, orderBy := feedSortColumns(tt.sort)
		if (scoreExpr != "") != tt.scored {
			t.Errorf("sort=%q: scored=%v but scoreExpr=%q", tt.sort, tt.scored, scoreExpr)
		}
		if tt.wantOrder == "ORDER BY" {
			if !strings.Contains(orderBy, "ORDER BY") {
				t.Errorf("sort=%q: orderBy missing ORDER BY: %q", tt.sort, orderBy)
			}
		} else if orderBy != tt.wantOrder {
			t.Errorf("sort=%q: orderBy=%q, want %q", tt.sort, orderBy, tt.wantOrder)
		}
		if tt.wantExpr != "" && !strings.Contains(scoreExpr, tt.wantExpr) {
			t.Errorf("sort=%q: scoreExpr=%q missing %q", tt.sort, scoreExpr, tt.wantExpr)
		}
	}
}

func TestRecommendationScoreSignals(t *testing.T) {
	score, order := feedSortColumns("recommended")
	for _, signal := range []string{"like_count", "unique_commenters", "external_comments", "bookmark_count", "share_count"} {
		if !strings.Contains(score, signal) {
			t.Errorf("recommended score missing %s: %s", signal, score)
		}
	}
	if strings.Contains(score, "view_count") || strings.Contains(score, "recommended_at") {
		t.Fatalf("recommended score contains forbidden signal: %s", score)
	}
	if !strings.Contains(order, "CASE WHEN hr.is_pinned") || !strings.Contains(order, "CASE WHEN NOT hr.is_pinned") {
		t.Fatalf("recommended order does not separate pinned and scored items: %s", order)
	}
}

func TestFeedSortColumnsDistinct(t *testing.T) {
	hot, _ := feedSortColumns("hot")
	featured, _ := feedSortColumns("featured")
	if hot == "" || featured == "" {
		t.Fatal("scored sorts must have a score expression")
	}
	if hot == featured {
		t.Errorf("featured and hot must use distinct formulas")
	}
}
