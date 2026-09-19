package api

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
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

func TestGetPublicActivityReturnsPublishedActivity(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	query := regexp.QuoteMeta(`
		SELECT a.id, a.title, a.description, COALESCE(a.cover_media_id, ''),
		       COALESCE(ma.object_key, a.cover_url, ''),
		       a.start_at, a.end_at, a.location, a.publication_status, a.created_by,
		       COALESCE(up.nickname, u.username, ''), a.published_at, a.created_at, a.updated_at
		FROM activities a
		JOIN users u ON u.id = a.created_by
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets ma ON ma.id = a.cover_media_id AND ma.deleted_at IS NULL
		WHERE a.id = $1 AND a.deleted_at IS NULL AND a.publication_status = 'published'`)
	now := time.Now().UTC()
	startAt := now.Add(24 * time.Hour)
	endAt := now.Add(48 * time.Hour)
	mock.ExpectQuery(query).WithArgs("activity-1").WillReturnRows(sqlmock.NewRows([]string{
		"id", "title", "description", "cover_media_id", "cover_key", "start_at", "end_at", "location", "publication_status", "created_by", "author_name", "published_at", "created_at", "updated_at",
	}).AddRow("activity-1", "周末活动", "一起交流", "", "", startAt, endAt, "线上", "published", "u1", "发起人", now, now, now))

	server := &Server{db: db}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/activities/activity-1", nil)
	res := httptest.NewRecorder()
	server.getPublicActivity(res, req, "activity-1")
	if res.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", res.Code, res.Body.String())
	}
	var body activityResponse
	if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.ID != "activity-1" || body.Title != "周末活动" || body.Status != "upcoming" {
		t.Fatalf("unexpected activity response: %+v", body)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestGetPublicActivityHidesUnavailableActivity(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	query := regexp.QuoteMeta(`
		SELECT a.id, a.title, a.description, COALESCE(a.cover_media_id, ''),
		       COALESCE(ma.object_key, a.cover_url, ''),
		       a.start_at, a.end_at, a.location, a.publication_status, a.created_by,
		       COALESCE(up.nickname, u.username, ''), a.published_at, a.created_at, a.updated_at
		FROM activities a
		JOIN users u ON u.id = a.created_by
		LEFT JOIN user_profiles up ON up.user_id = u.id
		LEFT JOIN media_assets ma ON ma.id = a.cover_media_id AND ma.deleted_at IS NULL
		WHERE a.id = $1 AND a.deleted_at IS NULL AND a.publication_status = 'published'`)
	mock.ExpectQuery(query).WithArgs("activity-hidden").WillReturnError(sql.ErrNoRows)

	server := &Server{db: db}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/activities/activity-hidden", nil)
	res := httptest.NewRecorder()
	server.getPublicActivity(res, req, "activity-hidden")
	if res.Code != http.StatusNotFound {
		t.Fatalf("status = %d, body = %s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
