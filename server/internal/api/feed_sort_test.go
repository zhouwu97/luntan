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
		{"recommended", false, "ORDER BY hr.position ASC, hr.recommended_at DESC, p.id DESC", ""},
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
