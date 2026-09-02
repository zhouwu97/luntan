package api

import (
	"database/sql/driver"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func rankingToyListMockRows() []string {
	return []string{
		"id", "rank", "name", "merchant", "release_year", "description",
		"tags", "asset_key", "want_count", "rating_total_centi", "rating_count",
		"category", "segments", "cover_media_id", "cover_object_key", "hero_media_id", "hero_object_key",
		"coupon_url", "source_url", "source_provider",
		"wanted", "owned", "rating",
	}
}

func rankingToyListMockRow(id string, sourceRank int, name string) []driver.Value {
	return []driver.Value{id, sourceRank, name, "", 2026, "简介", `["标签"]`, "hero.webp", 10, 870, 10, "cup", `["beginner"]`, "", "", "", "", "", "", "beiyoujiang", false, false, nil}
}

func expectWeeklyTopQuery(mock sqlmock.Sqlmock, tabKey, categoryKey string) {
	mock.ExpectQuery(`(?s)SELECT t\.id\s*FROM ranking_toy_rankings source_rank.*is_weekly_top = true`).
		WithArgs(tabKey, categoryKey).
		WillReturnRows(sqlmock.NewRows([]string{"id"}))
}

// 细分榜查询必须叠加人工排序覆盖层：LEFT JOIN ranking_manual_orders 并按
// position NULLS LAST, 源 rank 排序，保证覆盖层缺失时行为与旧逻辑一致。
func TestListRankingToysAppliesManualOrderOverlayToTabView(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	rows := sqlmock.NewRows(rankingToyListMockRows()).
		AddRow(rankingToyListMockRow("toy-c", 3, "人工第一")...).
		AddRow(rankingToyListMockRow("toy-a", 1, "源榜第一")...)
	mock.ExpectQuery(`(?s)LEFT JOIN ranking_manual_orders mo\s+ON mo\.toy_id = t\.id AND mo\.tab_key = \$2 AND mo\.category_key = \$3.*ORDER BY mo\.position ASC NULLS LAST, source_rank\.rank ASC, t\.id ASC`).
		WithArgs("", "ENTRY", "CUP").
		WillReturnRows(rows)
	expectWeeklyTopQuery(mock, "ENTRY", "CUP")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/ranking/toys?tab=ENTRY&category=CUP", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("榜单应返回 200，实际 %d：%s", res.Code, res.Body.String())
	}
	var body struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Items) != 2 {
		t.Fatalf("应返回 2 个商品：%s", res.Body.String())
	}
	if body.Items[0]["id"] != "toy-c" || body.Items[1]["id"] != "toy-a" {
		t.Fatalf("顺序应与查询结果一致：%#v", body.Items)
	}
	// rank 是当前视图的展示序号（1..N），源榜单名次经 source_rank 保留。
	if body.Items[0]["rank"] != float64(1) || body.Items[0]["source_rank"] != float64(3) {
		t.Fatalf("展示序号与源名次必须拆分：%#v", body.Items[0])
	}
	if body.Items[1]["rank"] != float64(2) || body.Items[1]["source_rank"] != float64(1) {
		t.Fatalf("展示序号与源名次必须拆分：%#v", body.Items[1])
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// 综合热榜视图键为 tab/category 双空，同样叠加覆盖层。
func TestListRankingToysAppliesManualOrderOverlayToOverallView(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	rows := sqlmock.NewRows(rankingToyListMockRows()).
		AddRow(rankingToyListMockRow("toy-manual", 9, "人工置顶")...).
		AddRow(rankingToyListMockRow("toy-first", 1, "源榜第一")...)
	mock.ExpectQuery(`(?s)LEFT JOIN ranking_manual_orders mo\s+ON mo\.toy_id = t\.id AND mo\.tab_key = '' AND mo\.category_key = ''.*ORDER BY mo\.position ASC NULLS LAST, t\.rank ASC, t\.id ASC`).
		WithArgs("").
		WillReturnRows(rows)
	expectWeeklyTopQuery(mock, "", "")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/ranking/toys", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("榜单应返回 200，实际 %d：%s", res.Code, res.Body.String())
	}
	var body struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Items) != 2 || body.Items[0]["id"] != "toy-manual" {
		t.Fatalf("综合榜应应用覆盖层顺序：%#v", body.Items)
	}
	if body.Items[0]["rank"] != float64(1) || body.Items[0]["source_rank"] != float64(9) {
		t.Fatalf("综合榜展示序号与源名次必须拆分：%#v", body.Items[0])
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
