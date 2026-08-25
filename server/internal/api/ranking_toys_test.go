package api

import "testing"

func TestRankingToyScoreUsesCentiUnits(t *testing.T) {
	tests := []struct {
		name       string
		totalCenti int64
		count      int64
		want       float64
	}{
		{name: "8.7", totalCenti: 14790, count: 17, want: 8.7},
		{name: "9.1", totalCenti: 81900, count: 90, want: 9.1},
		{name: "round half up", totalCenti: 17730, count: 20, want: 8.9},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			item := rankingToyRecord{RatingTotalCenti: tt.totalCenti, RatingCount: tt.count}
			if got := item.score(); got != tt.want {
				t.Fatalf("score() = %v, want %v", got, tt.want)
			}
		})
	}
}
