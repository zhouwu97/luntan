package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestHasAnyPermissionChecksGlobalRolePermission(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(regexp.QuoteMeta(`
		SELECT EXISTS (
			SELECT 1 FROM user_roles ur
			JOIN role_permissions rp ON rp.role_id = ur.role_id
			JOIN permissions p ON p.id = rp.permission_id
			WHERE ur.user_id = $1 AND p.name = $2
		)`)).WithArgs("user-1", "report.review").WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	if !(&Server{db: db}).hasAnyPermission(httptest.NewRequest("GET", "/api/v1/moderation/cases", nil), "user-1", "report.review") {
		t.Fatal("hasAnyPermission returned false for an allowed user")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestNormalizeModerationSourceFilterUsesStoredSourceNames(t *testing.T) {
	for input, want := range map[string]string{
		"":             "",
		"report":       "user_report",
		"user_report":  "user_report",
		"auto":         "auto_rule",
		"auto_rule":    "auto_rule",
		"manual_admin": "manual_admin",
	} {
		got, err := normalizeModerationSourceFilter(input)
		if err != nil {
			t.Fatalf("normalizeModerationSourceFilter(%q) error: %v", input, err)
		}
		if got != want {
			t.Errorf("normalizeModerationSourceFilter(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestNormalizeModerationSourceFilterRejectsUnknownSource(t *testing.T) {
	if _, err := normalizeModerationSourceFilter("unknown"); err == nil {
		t.Fatal("unknown moderation source should be rejected")
	}
}

func TestLoadModerationMediaEvidenceIncludesPostAndCommentAttachments(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT ma\.id, ma\.mime_type.*FROM post_media`).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "mime_type", "width", "height", "moderation_status"}).
			AddRow("media-post", "image/jpeg", 1200, 800, "normal"))
	mock.ExpectQuery(`(?s)SELECT ma\.id, ma\.mime_type.*FROM comment_media`).
		WithArgs("comment-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "mime_type", "width", "height", "moderation_status"}).
			AddRow("media-comment", "image/png", 640, 480, "censored"))

	s := &Server{db: db}
	postIDs, postMedia, err := s.loadModerationMediaEvidence(context.Background(), "post", "post-1")
	if err != nil {
		t.Fatalf("post evidence error: %v", err)
	}
	commentIDs, commentMedia, err := s.loadModerationMediaEvidence(context.Background(), "comment", "comment-1")
	if err != nil {
		t.Fatalf("comment evidence error: %v", err)
	}

	if len(postIDs) != 1 || postIDs[0] != "media-post" || postMedia[0]["preview_url"] != "/api/v1/admin/media/media-post/preview" {
		t.Fatalf("unexpected post evidence: ids=%v media=%v", postIDs, postMedia)
	}
	if len(commentIDs) != 1 || commentIDs[0] != "media-comment" || commentMedia[0]["moderation_status"] != "censored" {
		t.Fatalf("unexpected comment evidence: ids=%v media=%v", commentIDs, commentMedia)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestListModerationCasesFiltersSourceBeforeLimit(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	s := &Server{db: db}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/moderation/cases?status=pending&source=report&limit=1", nil)
	req = req.WithContext(context.WithValue(req.Context(), authenticatedUserContextKey{}, auth.User{ID: "moderator-1"}))
	mock.ExpectQuery(regexp.QuoteMeta(`
		SELECT EXISTS (
			SELECT 1 FROM user_roles ur
			JOIN role_permissions rp ON rp.role_id = ur.role_id
			JOIN permissions p ON p.id = rp.permission_id
			WHERE ur.user_id = $1 AND p.name = $2
		)`)).
		WithArgs("moderator-1", "report.review").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))
	mock.ExpectQuery(`(?s)SELECT mc\.id.*mc\.status = \$1.*mc\.source = \$2.*user_id = \$3.*LIMIT \$4`).
		WithArgs("open", "user_report", "moderator-1", 2).
		WillReturnRows(sqlmock.NewRows([]string{"id", "target_type", "target_id", "source", "risk_level", "status", "created_at", "resolved_at", "community_id"}).
			AddRow("case-1", "post", "post-1", "user_report", "low", "pending", time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC), nil, "community-1"))

	rec := httptest.NewRecorder()
	s.listModerationCases(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"source":"user_report"`) {
		t.Fatalf("list response: status=%d body=%s", rec.Code, rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
