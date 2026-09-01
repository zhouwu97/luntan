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

func TestListMediaModerationHistoryReturnsInitialAndModifiedStates(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	expectModerationPermission(mock)
	createdAt := time.Date(2026, 9, 1, 1, 2, 3, 0, time.UTC)
	mock.ExpectQuery(`(?s)SELECT id, version_no, moderation_status, mask_regions::text, operator_id, reason, created_at.*FROM media_moderation_versions.*WHERE media_id = \$1 OR media_id_snapshot = \$1.*ORDER BY version_no ASC`).
		WithArgs("media-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "version_no", "moderation_status", "mask_regions", "operator_id", "reason", "created_at"}).
			AddRow("version-1", 1, "normal", "[]", nil, "初始发布状态", createdAt).
			AddRow("version-2", 2, "censored", `[{"x":0.1,"y":0.2,"width":0.4,"height":0.3,"type":"mosaic"}]`, "admin-1", "隐藏敏感信息", createdAt.Add(time.Hour)))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/media/media-1/moderation-history", nil)
	req = req.WithContext(context.WithValue(req.Context(), authenticatedUserContextKey{}, auth.User{
		ID: "admin-1", AccountType: "email", Status: "active",
	}))
	rec := httptest.NewRecorder()
	(&Server{db: db}).listMediaModerationHistory(rec, req, "media-1")

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	var payload struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Items) != 2 || payload.Items[0]["version_no"] != float64(1) || payload.Items[1]["moderation_status"] != "censored" {
		t.Fatalf("unexpected history payload: %s", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "object_key") || strings.Contains(rec.Body.String(), "media/secret") {
		t.Fatalf("history response must not expose storage object keys: %s", rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
