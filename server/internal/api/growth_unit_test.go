package api

import "testing"

func TestSameStringSet(t *testing.T) {
	tests := []struct {
		name  string
		left  []string
		right []string
		want  bool
	}{
		{name: "same order", left: []string{"a", "b"}, right: []string{"a", "b"}, want: true},
		{name: "different order", left: []string{"a", "b"}, right: []string{"b", "a"}, want: true},
		{name: "different option", left: []string{"a"}, right: []string{"b"}, want: false},
		{name: "different length", left: []string{"a"}, right: []string{"a", "b"}, want: false},
		{name: "duplicate is not a set match", left: []string{"a", "a"}, right: []string{"a"}, want: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := sameStringSet(test.left, test.right); got != test.want {
				t.Fatalf("sameStringSet(%v, %v) = %v, want %v", test.left, test.right, got, test.want)
			}
		})
	}
}
