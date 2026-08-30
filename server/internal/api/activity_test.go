package api

import (
	"testing"
	"time"
)

func TestActivityPublicationStatusAndPhaseAreIndependent(t *testing.T) {
	now := time.Date(2026, 8, 30, 12, 0, 0, 0, time.UTC)
	future := now.Add(time.Hour)
	past := now.Add(-time.Hour)

	tests := []struct {
		name            string
		requestedStatus string
		startAt         *time.Time
		endAt           *time.Time
		wantPublication string
		wantStatus      string
		wantPhase       string
	}{
		{name: "draft remains unpublished", requestedStatus: "draft", startAt: &future, wantPublication: "draft", wantStatus: "draft"},
		{name: "offline remains unpublished", requestedStatus: "offline", startAt: &past, wantPublication: "offline", wantStatus: "offline"},
		{name: "future published activity is upcoming", requestedStatus: "active", startAt: &future, wantPublication: "published", wantStatus: "upcoming", wantPhase: "upcoming"},
		{name: "running published activity is active", requestedStatus: "upcoming", startAt: &past, endAt: &future, wantPublication: "published", wantStatus: "active", wantPhase: "active"},
		{name: "ended published activity is ended", requestedStatus: "ended", startAt: &past, endAt: &past, wantPublication: "published", wantStatus: "ended", wantPhase: "ended"},
		{name: "invalid manual phase is canonicalized", requestedStatus: "ended", wantPublication: "published", wantStatus: "active", wantPhase: "active"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			publication := activityPublicationStatus(test.requestedStatus)
			status := activityStatusForResponse(publication, test.startAt, test.endAt, now)
			phase := activityPhaseForPublication(publication, test.startAt, test.endAt, now)
			if publication != test.wantPublication || status != test.wantStatus || phase != test.wantPhase {
				t.Fatalf("publication=%q status=%q phase=%q，期望 publication=%q status=%q phase=%q", publication, status, phase, test.wantPublication, test.wantStatus, test.wantPhase)
			}
		})
	}
}
