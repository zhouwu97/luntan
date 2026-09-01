package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestRiskOverviewIncludesSafeTargetContext(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	user := auth.User{ID: "admin-1", AccountType: "email", Status: "active"}
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*p\.name = \$2.*`).
		WithArgs("admin-1", "audit.read").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))
	mock.ExpectQuery(`SELECT count\(\*\) FROM risk_events WHERE event_type = 'email_code_requested'`).
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(2))
	mock.ExpectQuery(`(?s)SELECT count\(\*\) FROM \(SELECT ip_address FROM risk_events`).
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(1))
	mock.ExpectQuery(`SELECT count\(\*\) FROM risk_events WHERE event_type = 'content_auto_review'`).
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(3))
	mock.ExpectQuery(`(?s)SELECT re\.id, re\.event_type.*target_title.*content_preview.*account_name.*account_email.*FROM risk_events re`).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "event_type", "severity", "ip_address", "metadata", "created_at",
			"target_type", "target_id", "target_title", "content_preview", "account_name", "account_email",
		}).AddRow(
			"risk-1", "content_auto_review", "medium", "203.0.113.8",
			`{"target_type":"post","target_id":"post-1","email":"raw@example.com"}`,
			time.Date(2026, 9, 1, 1, 2, 3, 0, time.UTC), "post", "post-1", "帖子标题", "帖子正文内容", "账号昵称", "raw@example.com",
		))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/risk", nil)
	req = req.WithContext(context.WithValue(req.Context(), authenticatedUserContextKey{}, user))
	rec := httptest.NewRecorder()
	(&Server{db: db}).riskOverview(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	var payload struct {
		Events []map[string]any `json:"events"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Events) != 1 || payload.Events[0]["target_title"] != "帖子标题" || payload.Events[0]["email"] != "r***@example.com" {
		t.Fatalf("unexpected safe context: %s", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "raw@example.com") || strings.Contains(rec.Body.String(), `"metadata"`) {
		t.Fatalf("risk response leaked private metadata: %s", rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestEmailRiskMetadataStoresMaskedEmail(t *testing.T) {
	metadata := string(emailRiskMetadata("person@example.com"))
	if !strings.Contains(metadata, "p***@example.com") {
		t.Fatalf("masked email missing from risk metadata: %s", metadata)
	}
	if strings.Contains(metadata, "person@example.com") {
		t.Fatalf("risk metadata must not contain the raw email: %s", metadata)
	}
}
