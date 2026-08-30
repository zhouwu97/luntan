package httpserver

import (
	"net/http"
	"testing"
)

func TestCommentBusinessMetricCountsOnlyWriteRequests(t *testing.T) {
	metric := &requestMetrics{}
	metric.observeBusiness(http.MethodGet, "/api/v1/posts/post-1/comments", http.StatusOK)
	metric.observeBusiness(http.MethodPost, "/api/v1/posts/post-1/comments", http.StatusCreated)
	metric.observeBusiness(http.MethodPost, "/api/v1/posts/post-1/comments", http.StatusBadRequest)

	if got := metric.comment.attempts.Load(); got != 2 {
		t.Fatalf("comment attempts = %d, want 2", got)
	}
	if got := metric.comment.success.Load(); got != 1 {
		t.Fatalf("comment successes = %d, want 1", got)
	}
}
