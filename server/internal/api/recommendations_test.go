package api

import "testing"

func TestValidateRecommendationOrder(t *testing.T) {
	current := map[string]struct{}{"a": {}, "b": {}, "c": {}}
	tests := []struct {
		name  string
		items []reorderRecommendationItem
		valid bool
	}{
		{name: "continuous order", items: []reorderRecommendationItem{{PostID: "b", Position: 1}, {PostID: "a", Position: 2}, {PostID: "c", Position: 3}}, valid: true},
		{name: "duplicate post", items: []reorderRecommendationItem{{PostID: "a", Position: 1}, {PostID: "a", Position: 2}, {PostID: "c", Position: 3}}},
		{name: "duplicate position", items: []reorderRecommendationItem{{PostID: "a", Position: 1}, {PostID: "b", Position: 1}, {PostID: "c", Position: 2}}},
		{name: "unknown post", items: []reorderRecommendationItem{{PostID: "a", Position: 1}, {PostID: "b", Position: 2}, {PostID: "x", Position: 3}}},
		{name: "non continuous position", items: []reorderRecommendationItem{{PostID: "a", Position: 1}, {PostID: "b", Position: 2}, {PostID: "c", Position: 4}}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, valid := validateRecommendationOrder(test.items, current)
			if valid != test.valid {
				t.Fatalf("valid = %v, want %v", valid, test.valid)
			}
		})
	}
}
