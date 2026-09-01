package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestStoreProductImagesAreExposedByCatalogAndServer(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(regexp.QuoteMeta(`
		SELECT p.id, p.name, p.description, p.emoji, p.points, p.color,
		       COUNT(o.id) FILTER (WHERE o.status IN ('claimed', 'completed')) AS redeemed_count
		FROM store_products p
		LEFT JOIN store_orders o ON o.product_id = p.id
		WHERE p.active = true
		GROUP BY p.id, p.name, p.description, p.emoji, p.points, p.color
		ORDER BY redeemed_count DESC, p.points ASC, p.id ASC`)).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "name", "description", "emoji", "points", "color", "redeemed_count",
		}).AddRow("badge", "论坛纪念徽章", "论坛限定周边", "🏅", 60, 16766842, 0))

	handler := NewHandler(db)
	catalogResponse := httptest.NewRecorder()
	handler.ServeHTTP(catalogResponse, httptest.NewRequest(http.MethodGet, "/api/v1/store/products", nil))
	if catalogResponse.Code != http.StatusOK {
		t.Fatalf("catalog status = %d, body = %s", catalogResponse.Code, catalogResponse.Body.String())
	}
	var catalog map[string]any
	if err := json.Unmarshal(catalogResponse.Body.Bytes(), &catalog); err != nil {
		t.Fatal(err)
	}
	items, ok := catalog["items"].([]any)
	if !ok || len(items) != 1 {
		t.Fatalf("catalog items = %#v", catalog["items"])
	}
	item, ok := items[0].(map[string]any)
	if !ok || item["image_url"] != "/api/v1/store/products/badge/image" {
		t.Fatalf("catalog image_url = %#v", item)
	}

	imageResponse := httptest.NewRecorder()
	handler.ServeHTTP(imageResponse, httptest.NewRequest(http.MethodGet, "/api/v1/store/products/badge/image", nil))
	if imageResponse.Code != http.StatusOK {
		t.Fatalf("image status = %d, body = %s", imageResponse.Code, imageResponse.Body.String())
	}
	if imageResponse.Header().Get("Content-Type") != "image/jpeg" {
		t.Fatalf("image content type = %q", imageResponse.Header().Get("Content-Type"))
	}
	if imageResponse.Body.Len() == 0 {
		t.Fatal("image body is empty")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
