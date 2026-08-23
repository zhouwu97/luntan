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
		{"recommended", true, "ORDER BY", "POWER"},
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
	recommended, _ := feedSortColumns("recommended")
	hot, _ := feedSortColumns("hot")
	featured, _ := feedSortColumns("featured")
	if recommended == "" || hot == "" || featured == "" {
		t.Fatal("scored sorts must have a score expression")
	}
	if recommended == hot {
		t.Errorf("recommended and hot must use different formulas")
	}
	if recommended == featured || hot == featured {
		t.Errorf("featured must use a distinct formula")
	}
}
