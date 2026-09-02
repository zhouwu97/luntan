package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

func rankingViewSeedToyIn(t *testing.T, s *Server, tag string, seq int, tabKey, categoryKey string, viewRank int) string {
	t.Helper()
	toyID := fmt.Sprintf("itest-viewtoy-%s-%d-%d", tag, time.Now().UnixNano(), seq)
	if _, err := s.db.Exec(`INSERT INTO ranking_toys (id, rank, name) VALUES ($1, $2, $3)`,
		toyID, viewRank, fmt.Sprintf("覆盖层测试杯%d", seq)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`
		INSERT INTO ranking_toy_rankings (source_provider, view_key, tab_key, category_key, toy_id, rank, snapshot_fetched_at)
		VALUES ('beiyoujiang', $2 || '|' || $3, $2, $3, $1, $4, now())`, toyID, tabKey, categoryKey, viewRank); err != nil {
		t.Fatal(err)
	}
	return toyID
}

func rankingViewSeedToy(t *testing.T, s *Server, tag string, seq, viewRank int) string {
	t.Helper()
	return rankingViewSeedToyIn(t, s, tag, seq, "HIGH", "LUBE", viewRank)
}

type rankingViewPublicOrder struct {
	IDs         []string
	Ranks       map[string]int
	SourceRanks map[string]int
}

func rankingViewFetchPublicOrder(t *testing.T, handler http.Handler, path string) rankingViewPublicOrder {
	t.Helper()
	code, body := callBusinessAPI(handler, http.MethodGet, path, "", nil, nil)
	if code != http.StatusOK {
		t.Fatalf("公开榜单 %s 应返回 200，实际 %d：%s", path, code, body)
	}
	var payload struct {
		Items []struct {
			ID         string `json:"id"`
			Rank       int    `json:"rank"`
			SourceRank int    `json:"source_rank"`
		} `json:"items"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		t.Fatal(err)
	}
	order := rankingViewPublicOrder{Ranks: map[string]int{}, SourceRanks: map[string]int{}}
	for _, item := range payload.Items {
		order.IDs = append(order.IDs, item.ID)
		order.Ranks[item.ID] = item.Rank
		order.SourceRanks[item.ID] = item.SourceRank
	}
	return order
}

func rankingViewAdminGet(t *testing.T, handler http.Handler, token, path string) (sortMode string, version float64, items []map[string]any) {
	t.Helper()
	code, body := callBusinessAPI(handler, http.MethodGet, path, token, nil, nil)
	if code != http.StatusOK {
		t.Fatalf("admin view GET %s 应返回 200，实际 %d：%s", path, code, body)
	}
	var payload struct {
		View struct {
			SortMode string  `json:"sort_mode"`
			Version  float64 `json:"version"`
		} `json:"view"`
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		t.Fatal(err)
	}
	return payload.View.SortMode, payload.View.Version, payload.Items
}

func rankingViewIndexOf(ids []string, toyID string) int {
	for index, id := range ids {
		if id == toyID {
			return index
		}
	}
	return -1
}

// 完整生命周期：AUTO 初始态 → 人工排序覆盖公开榜单（源 rank 保留）→
// version 乐观锁 409 → 普通管理员 403 → 新同步商品排在人工项之后 → 恢复 AUTO。
func TestRankingViewManualOrderLifecycle(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)
	superEmail, _, superToken := rankingSubmissionTestUser(t, s, handler, "vieword")
	promoteSuperAdmin(t, s, superEmail)
	superToken = loginUser(t, handler, superEmail, "password123")

	var base int
	if err := s.db.QueryRow(`SELECT COALESCE(MAX(rank), 0) FROM ranking_toy_rankings WHERE source_provider = 'beiyoujiang' AND tab_key = 'HIGH' AND category_key = 'LUBE'`).Scan(&base); err != nil {
		t.Fatal(err)
	}
	toyA := rankingViewSeedToy(t, s, "lo", 1, base+1)
	toyB := rankingViewSeedToy(t, s, "lo", 2, base+2)
	toyC := rankingViewSeedToy(t, s, "lo", 3, base+3)
	viewToys := []string{toyA, toyB, toyC}
	publicPath := "/api/v1/ranking/toys?tab=HIGH&category=LUBE"
	adminPath := "/api/v1/admin/ranking/views?tab=HIGH&category=LUBE"
	orderPath := "/api/v1/admin/ranking/views/order"
	t.Cleanup(func() {
		for _, toyID := range viewToys {
			_, _ = s.db.Exec(`UPDATE ranking_toys SET active = false WHERE id = $1`, toyID)
		}
		_, _ = s.db.Exec(`DELETE FROM ranking_manual_orders WHERE (tab_key = 'HIGH' AND category_key = 'LUBE') OR (tab_key = '' AND category_key = '')`)
		_, _ = s.db.Exec(`DELETE FROM ranking_view_settings WHERE (tab_key = 'HIGH' AND category_key = 'LUBE') OR (tab_key = '' AND category_key = '')`)
	})

	// 1) 初始 AUTO：admin 视图按源顺序展示，version 0，无人工位次。
	sortMode, version, items := rankingViewAdminGet(t, handler, superToken, adminPath)
	if sortMode != "AUTO" || version != 0 {
		t.Fatalf("初始视图应为 AUTO/version 0，实际 %s/%v", sortMode, version)
	}
	if rankingViewIndexOf(toyIDs(items), toyA) > rankingViewIndexOf(toyIDs(items), toyB) || rankingViewIndexOf(toyIDs(items), toyB) > rankingViewIndexOf(toyIDs(items), toyC) {
		t.Fatalf("AUTO 顺序应与源榜单一致：%v", toyIDs(items))
	}

	// 2) 公开榜单初始顺序 = 源顺序。
	publicOrder := rankingViewFetchPublicOrder(t, handler, publicPath)
	if rankingViewIndexOf(publicOrder.IDs, toyA) > rankingViewIndexOf(publicOrder.IDs, toyB) {
		t.Fatalf("公开榜单初始顺序错误：%v", publicOrder.IDs)
	}

	// 3) 保存人工顺序 [C,B,A]。
	code, body := callBusinessAPI(handler, http.MethodPut, orderPath, superToken, map[string]any{
		"tab": "HIGH", "category": "LUBE", "mode": "MANUAL",
		"ordered_toy_ids": []string{toyC, toyB, toyA}, "version": 0,
	}, nil)
	if code != http.StatusOK {
		t.Fatalf("保存人工排序应返回 200，实际 %d：%s", code, body)
	}

	// 4) admin 视图：MANUAL + version 1，展示顺序 C,B,A，源名次不变。
	sortMode, version, items = rankingViewAdminGet(t, handler, superToken, adminPath)
	if sortMode != "MANUAL" || version != 1 {
		t.Fatalf("保存后应为 MANUAL/version 1，实际 %s/%v", sortMode, version)
	}
	ids := toyIDs(items)
	if len(ids) < 3 || ids[0] != toyC || ids[1] != toyB || ids[2] != toyA {
		t.Fatalf("admin 视图顺序应为 C,B,A：%v", ids)
	}
	if items[0]["manual_position"] != float64(1) || items[2]["manual_position"] != float64(3) {
		t.Fatalf("人工位次错误：%v %v", items[0]["manual_position"], items[2]["manual_position"])
	}
	if items[0]["source_rank"] != float64(base+3) {
		t.Fatalf("源名次必须保留，实际 %v（期望 %d）", items[0]["source_rank"], base+3)
	}

	// 5) 公开榜单：人工顺序生效，rank 字段仍是源名次。
	publicOrder = rankingViewFetchPublicOrder(t, handler, publicPath)
	if len(publicOrder.IDs) < 3 || publicOrder.IDs[0] != toyC || publicOrder.IDs[1] != toyB || publicOrder.IDs[2] != toyA {
		t.Fatalf("公开榜单应为 C,B,A：%v", publicOrder.IDs)
	}
	if publicOrder.Ranks[toyC] != base+3 {
		t.Fatalf("公开接口 rank 应回源名次，实际 %d", publicOrder.Ranks[toyC])
	}

	// 6) version 过期 → 409。
	code, body = callBusinessAPI(handler, http.MethodPut, orderPath, superToken, map[string]any{
		"tab": "HIGH", "category": "LUBE", "mode": "MANUAL",
		"ordered_toy_ids": []string{toyA, toyB, toyC}, "version": 0,
	}, nil)
	if code != http.StatusConflict || !strings.Contains(string(body), "RANKING_VIEW_ORDER_STALE") {
		t.Fatalf("过期 version 应返回 409，实际 %d：%s", code, body)
	}

	// 7) 含未知商品 → 409。
	code, body = callBusinessAPI(handler, http.MethodPut, orderPath, superToken, map[string]any{
		"tab": "HIGH", "category": "LUBE", "mode": "MANUAL",
		"ordered_toy_ids": []string{toyC, toyB, toyA, "toy-not-exist"}, "version": 1,
	}, nil)
	if code != http.StatusConflict {
		t.Fatalf("未知商品应返回 409，实际 %d：%s", code, body)
	}

	// 8) 普通管理员 403，匿名 401。
	moderatorEmail, _, moderatorToken := rankingSubmissionTestUser(t, s, handler, "viewmod")
	promoteRoleByEmail(t, s, moderatorEmail, "platform_moderator")
	moderatorToken = loginUser(t, handler, moderatorEmail, "password123")
	code, _ = callBusinessAPI(handler, http.MethodPut, orderPath, moderatorToken, map[string]any{
		"tab": "HIGH", "category": "LUBE", "mode": "MANUAL",
		"ordered_toy_ids": []string{toyC, toyB, toyA}, "version": 1,
	}, nil)
	if code != http.StatusForbidden {
		t.Fatalf("普通管理员应返回 403，实际 %d", code)
	}
	code, _ = callBusinessAPI(handler, http.MethodPut, orderPath, "", map[string]any{
		"tab": "HIGH", "category": "LUBE", "mode": "MANUAL",
		"ordered_toy_ids": []string{toyC, toyB, toyA}, "version": 1,
	}, nil)
	if code != http.StatusUnauthorized {
		t.Fatalf("匿名应返回 401，实际 %d", code)
	}

	// 9) 模拟外部同步新增 D：无人工位次，排在人工项之后（NEW 待排序）。
	toyD := rankingViewSeedToy(t, s, "lo", 4, base+4)
	viewToys = append(viewToys, toyD)
	publicOrder = rankingViewFetchPublicOrder(t, handler, publicPath)
	if len(publicOrder.IDs) < 4 || publicOrder.IDs[3] != toyD {
		t.Fatalf("新同步商品应排在人工项之后：%v", publicOrder.IDs)
	}
	_, _, items = rankingViewAdminGet(t, handler, superToken, adminPath)
	if items[3]["manual_position"] != nil {
		t.Fatalf("新同步商品应无人工位次（NEW 待排序）：%v", items[3])
	}

	// 10) 把 D 纳入人工顺序。
	code, body = callBusinessAPI(handler, http.MethodPut, orderPath, superToken, map[string]any{
		"tab": "HIGH", "category": "LUBE", "mode": "MANUAL",
		"ordered_toy_ids": []string{toyC, toyD, toyB, toyA}, "version": 1,
	}, nil)
	if code != http.StatusOK {
		t.Fatalf("纳入新商品应返回 200，实际 %d：%s", code, body)
	}
	publicOrder = rankingViewFetchPublicOrder(t, handler, publicPath)
	if publicOrder.IDs[0] != toyC || publicOrder.IDs[1] != toyD {
		t.Fatalf("人工顺序应为 C,D,B,A：%v", publicOrder.IDs)
	}

	// 11) 恢复自动排序：覆盖层清空，回到源顺序。
	code, body = callBusinessAPI(handler, http.MethodPut, orderPath, superToken, map[string]any{
		"tab": "HIGH", "category": "LUBE", "mode": "AUTO", "ordered_toy_ids": []string{}, "version": 2,
	}, nil)
	if code != http.StatusOK {
		t.Fatalf("恢复自动排序应返回 200，实际 %d：%s", code, body)
	}
	sortMode, version, _ = rankingViewAdminGet(t, handler, superToken, adminPath)
	if sortMode != "AUTO" || version != 3 {
		t.Fatalf("恢复后应为 AUTO/version 3，实际 %s/%v", sortMode, version)
	}
	publicOrder = rankingViewFetchPublicOrder(t, handler, publicPath)
	a, b := rankingViewIndexOf(publicOrder.IDs, toyA), rankingViewIndexOf(publicOrder.IDs, toyB)
	c, d := rankingViewIndexOf(publicOrder.IDs, toyC), rankingViewIndexOf(publicOrder.IDs, toyD)
	if !(a < b && b < c && c < d) {
		t.Fatalf("恢复自动后应回到源顺序 A,B,C,D：%v", publicOrder.IDs)
	}
}

// 综合热榜（tab/category 双空）同样支持覆盖层，且只要求提交子集也合法。
func TestRankingViewManualOrderOverallView(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)
	superEmail, _, superToken := rankingSubmissionTestUser(t, s, handler, "viewall")
	promoteSuperAdmin(t, s, superEmail)
	superToken = loginUser(t, handler, superEmail, "password123")

	var base int
	if err := s.db.QueryRow(`SELECT COALESCE(MAX(rank), 0) FROM ranking_toys`).Scan(&base); err != nil {
		t.Fatal(err)
	}
	toyX := fmt.Sprintf("itest-viewtoy-all-%d", time.Now().UnixNano())
	if _, err := s.db.Exec(`INSERT INTO ranking_toys (id, rank, name) VALUES ($1, $2, $3)`, toyX, base+1, "综合榜覆盖测试杯"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = s.db.Exec(`UPDATE ranking_toys SET active = false WHERE id = $1`, toyX)
		_, _ = s.db.Exec(`DELETE FROM ranking_manual_orders WHERE tab_key = '' AND category_key = ''`)
		_, _ = s.db.Exec(`DELETE FROM ranking_view_settings WHERE tab_key = '' AND category_key = ''`)
	})

	publicPath := "/api/v1/ranking/toys"
	adminPath := "/api/v1/admin/ranking/views"
	orderPath := "/api/v1/admin/ranking/views/order"

	sortMode, version, _ := rankingViewAdminGet(t, handler, superToken, adminPath)
	if sortMode != "AUTO" || version != 0 {
		t.Fatalf("综合榜初始应为 AUTO/version 0，实际 %s/%v", sortMode, version)
	}

	order := rankingViewFetchPublicOrder(t, handler, publicPath)
	if order.IDs[len(order.IDs)-1] != toyX {
		t.Fatalf("最大 rank 的玩具应在综合榜末尾：%v", order.IDs)
	}

	code, body := callBusinessAPI(handler, http.MethodPut, orderPath, superToken, map[string]any{
		"tab": "", "category": "", "mode": "MANUAL", "ordered_toy_ids": []string{toyX}, "version": 0,
	}, nil)
	if code != http.StatusOK {
		t.Fatalf("综合榜人工排序应返回 200，实际 %d：%s", code, body)
	}

	order = rankingViewFetchPublicOrder(t, handler, publicPath)
	if order.IDs[0] != toyX {
		t.Fatalf("综合榜第一应为人工置顶商品：%v", order.IDs)
	}
	sortMode, _, _ = rankingViewAdminGet(t, handler, superToken, adminPath)
	if sortMode != "MANUAL" {
		t.Fatalf("综合榜应为 MANUAL：%s", sortMode)
	}

	code, body = callBusinessAPI(handler, http.MethodPut, orderPath, superToken, map[string]any{
		"tab": "", "category": "", "mode": "AUTO", "ordered_toy_ids": []string{}, "version": 1,
	}, nil)
	if code != http.StatusOK {
		t.Fatalf("综合榜恢复自动应返回 200，实际 %d：%s", code, body)
	}
	order = rankingViewFetchPublicOrder(t, handler, publicPath)
	if order.IDs[len(order.IDs)-1] != toyX {
		t.Fatalf("恢复自动后玩具应回到末尾：%v", order.IDs)
	}
}

// 视图参数与请求体校验。
func TestRankingViewOrderValidation(t *testing.T) {
	s := feedIntegrationServer(t)
	handler := NewHandler(s.db)
	superEmail, _, superToken := rankingSubmissionTestUser(t, s, handler, "viewvalid")
	promoteSuperAdmin(t, s, superEmail)
	superToken = loginUser(t, handler, superEmail, "password123")
	orderPath := "/api/v1/admin/ranking/views/order"

	cases := []struct {
		name   string
		body   map[string]any
		status int
		code   string
	}{
		{"刺激度缺品类", map[string]any{"tab": "HIGH", "category": "", "mode": "MANUAL", "ordered_toy_ids": []string{"x"}, "version": 0}, http.StatusBadRequest, "INVALID_RANKING_VIEW"},
		{"未知 tab", map[string]any{"tab": "BOGUS", "category": "LUBE", "mode": "MANUAL", "ordered_toy_ids": []string{"x"}, "version": 0}, http.StatusBadRequest, "INVALID_RANKING_VIEW"},
		{"未知 mode", map[string]any{"tab": "HIGH", "category": "LUBE", "mode": "WEIRD", "ordered_toy_ids": []string{"x"}, "version": 0}, http.StatusBadRequest, "INVALID_RANKING_VIEW_MODE"},
		{"MANUAL 空顺序", map[string]any{"tab": "HIGH", "category": "LUBE", "mode": "MANUAL", "ordered_toy_ids": []string{}, "version": 0}, http.StatusBadRequest, "INVALID_RANKING_VIEW_ORDER"},
	}
	for _, testCase := range cases {
		code, body := callBusinessAPI(handler, http.MethodPut, orderPath, superToken, testCase.body, nil)
		if code != testCase.status || !strings.Contains(string(body), testCase.code) {
			t.Fatalf("%s：期望 %d/%s，实际 %d：%s", testCase.name, testCase.status, testCase.code, code, body)
		}
	}

	code, body := callBusinessAPI(handler, http.MethodGet, "/api/v1/admin/ranking/views?tab=HIGH", superToken, nil, nil)
	if code != http.StatusBadRequest {
		t.Fatalf("GET 缺品类应返回 400，实际 %d：%s", code, body)
	}
}

func toyIDs(items []map[string]any) []string {
	ids := make([]string, 0, len(items))
	for _, item := range items {
		if id, ok := item["toy_id"].(string); ok {
			ids = append(ids, id)
		}
	}
	return ids
}
