package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

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

func TestGetPollDoesNotExposeVoteCapabilityToGuests(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id, question, allow_multiple, ends_at FROM polls WHERE post_id = $1`)).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "question", "allow_multiple", "ends_at"}).AddRow("poll-1", "选择", false, nil))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id, label, sort_order, vote_count FROM poll_options WHERE poll_id = $1 ORDER BY sort_order ASC, id ASC`)).
		WithArgs("poll-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "label", "sort_order", "vote_count"}).
			AddRow("option-1", "A", 0, 1).
			AddRow("option-2", "B", 1, 2))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/posts/post-1/poll", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("poll response: status=%d body=%s", res.Code, res.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(res.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	viewerState, ok := payload["viewer_state"].(map[string]any)
	if !ok {
		t.Fatalf("viewer_state missing: %#v", payload)
	}
	if viewerState["can_vote"] != false || viewerState["authentication_required"] != true {
		t.Fatalf("guest viewer state = %#v", viewerState)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
