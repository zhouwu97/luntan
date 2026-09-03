package api

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

// 榜单视图排序管理。源榜单名次（ranking_toys.rank /
// ranking_toy_rankings.rank）由外部导入维护，这里只读写覆盖层
// ranking_view_settings 与 ranking_manual_orders，保证重新导入不会
// 冲掉管理员的人工顺序，也永久保留原始排名。

// 词汇表与源站快照（scripts/sync_beiyoujiang_rankings.ps1）保持一致；
// 刺激度视图必须绑定品类，与导入器的视图枚举规则相同。
var (
	rankingViewTabs = map[string]struct{}{
		"":         {},
		"ENTRY":    {},
		"ADVANCED": {},
		"HIGH":     {},
		"EXTREME":  {},
	}
	rankingViewCategories = map[string]struct{}{
		"":           {},
		"CUP":        {},
		"SMALL_MOLD": {},
		"LARGE_MOLD": {},
		"HALF_BODY":  {},
		"LUBE":       {},
	}
)

// 与导入任务的名次锁分开：覆盖层不参与 ranking_toys.rank 重排，避免互相阻塞。
const rankingViewOrderLock = `SELECT pg_advisory_xact_lock(hashtext('luntan:ranking_view_order'))`

func normalizeRankingViewKeys(tab, category string) (string, string, bool) {
	tab = strings.ToUpper(strings.TrimSpace(tab))
	category = strings.ToUpper(strings.TrimSpace(category))
	if _, ok := rankingViewTabs[tab]; !ok {
		return "", "", false
	}
	if _, ok := rankingViewCategories[category]; !ok {
		return "", "", false
	}
	if tab != "" && category == "" {
		return "", "", false
	}
	return tab, category, true
}

type rankingViewSettings struct {
	Mode      string
	Version   int64
	UpdatedBy string
	UpdatedAt sql.NullTime
}

func loadRankingViewSettings(ctx context.Context, scanner interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}, tabKey, categoryKey string) (rankingViewSettings, error) {
	var settings rankingViewSettings
	err := scanner.QueryRowContext(ctx, `
		SELECT sort_mode, version, COALESCE(updated_by, ''), updated_at
		FROM ranking_view_settings WHERE tab_key = $1 AND category_key = $2`,
		tabKey, categoryKey).Scan(&settings.Mode, &settings.Version, &settings.UpdatedBy, &settings.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return rankingViewSettings{Mode: "AUTO"}, nil
	}
	if err != nil {
		return rankingViewSettings{}, err
	}
	return settings, nil
}

func (s *Server) adminRankingView(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	if _, ok := s.requireAdminRoleManager(w, r); !ok {
		return
	}
	tabKey, categoryKey, valid := normalizeRankingViewKeys(r.URL.Query().Get("tab"), r.URL.Query().Get("category"))
	if !valid {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_RANKING_VIEW", Message: "榜单视图参数无效"})
		return
	}
	settings, err := loadRankingViewSettings(r.Context(), s.db, tabKey, categoryKey)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	type viewItem struct {
		ToyID          string
		Name           string
		CoverMediaID   string
		CoverObjectKey string
		SourceRank     int
		ManualPosition sql.NullInt64
	}
	var items []viewItem
	var syncedAt sql.NullTime
	if tabKey != "" || categoryKey != "" {
		rows, err := s.db.QueryContext(r.Context(), `
			SELECT t.id, t.name, COALESCE(cover.id, ''), COALESCE(cover.object_key, ''),
			       source_rank.rank, mo.position
			FROM ranking_toy_rankings source_rank
			JOIN ranking_toys t ON t.id = source_rank.toy_id
			LEFT JOIN ranking_manual_orders mo
			  ON mo.toy_id = t.id AND mo.tab_key = $1 AND mo.category_key = $2
			LEFT JOIN media_assets cover ON cover.id = t.cover_media_id AND cover.status = 'ready' AND cover.deleted_at IS NULL
			WHERE source_rank.source_provider = 'beiyoujiang'
			  AND source_rank.tab_key = $1 AND source_rank.category_key = $2
			  AND t.active = true
			ORDER BY mo.position ASC NULLS LAST, source_rank.rank ASC, t.id ASC`, tabKey, categoryKey)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		defer rows.Close()
		for rows.Next() {
			var item viewItem
			if err := rows.Scan(&item.ToyID, &item.Name, &item.CoverMediaID, &item.CoverObjectKey, &item.SourceRank, &item.ManualPosition); err != nil {
				writeInternalError(w, r, err)
				return
			}
			items = append(items, item)
		}
		if err := rows.Err(); err != nil {
			writeInternalError(w, r, err)
			return
		}
		err = s.db.QueryRowContext(r.Context(), `
			SELECT MAX(snapshot_fetched_at) FROM ranking_toy_rankings
			WHERE source_provider = 'beiyoujiang' AND tab_key = $1 AND category_key = $2`,
			tabKey, categoryKey).Scan(&syncedAt)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	} else {
		rows, err := s.db.QueryContext(r.Context(), `
			SELECT t.id, t.name, COALESCE(cover.id, ''), COALESCE(cover.object_key, ''),
			       t.rank, mo.position
			FROM ranking_toys t
			LEFT JOIN ranking_manual_orders mo
			  ON mo.toy_id = t.id AND mo.tab_key = '' AND mo.category_key = ''
			LEFT JOIN media_assets cover ON cover.id = t.cover_media_id AND cover.status = 'ready' AND cover.deleted_at IS NULL
			WHERE t.active = true
			ORDER BY mo.position ASC NULLS LAST, t.rank ASC, t.id ASC`)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		defer rows.Close()
		for rows.Next() {
			var item viewItem
			if err := rows.Scan(&item.ToyID, &item.Name, &item.CoverMediaID, &item.CoverObjectKey, &item.SourceRank, &item.ManualPosition); err != nil {
				writeInternalError(w, r, err)
				return
			}
			items = append(items, item)
		}
		if err := rows.Err(); err != nil {
			writeInternalError(w, r, err)
			return
		}
		err = s.db.QueryRowContext(r.Context(), `
			SELECT MAX(COALESCE(source_updated_at, updated_at)) FROM ranking_toys`).Scan(&syncedAt)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
	}

	if items == nil {
		items = []viewItem{}
	}
	itemPayloads := make([]map[string]any, 0, len(items))
	for index, item := range items {
		var manualPosition any
		if item.ManualPosition.Valid {
			manualPosition = item.ManualPosition.Int64
		}
		itemPayloads = append(itemPayloads, map[string]any{
			"toy_id":           item.ToyID,
			"name":             item.Name,
			"cover_url":        mediaVariantURL(item.CoverMediaID, item.CoverObjectKey, "thumb"),
			"source_rank":      item.SourceRank,
			"manual_position":  manualPosition,
			"display_position": index + 1,
		})
	}
	var updatedAt any
	if settings.UpdatedAt.Valid {
		updatedAt = settings.UpdatedAt.Time
	}
	var syncedAtValue any
	if syncedAt.Valid {
		syncedAtValue = syncedAt.Time
	}
	// 本周推荐位独立于人工排序（始终置顶展示），后台单独呈现避免管理员
	// 误以为拖到列表第一就是首页大卡。
	var weeklyTopPayload any
	if top := s.loadWeeklyTopToy(r.Context(), "", tabKey, categoryKey); top != nil {
		weeklyTopPayload = map[string]any{
			"toy_id":      top.ID,
			"name":        top.Name,
			"cover_url":   mediaVariantURL(top.CoverMediaID, top.CoverObjectKey, "thumb"),
			"source_rank": top.Rank,
		}
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"view": map[string]any{
			"tab":        tabKey,
			"category":   categoryKey,
			"sort_mode":  settings.Mode,
			"version":    settings.Version,
			"updated_by": settings.UpdatedBy,
			"updated_at": updatedAt,
		},
		"items":      itemPayloads,
		"synced_at":  syncedAtValue,
		"weekly_top": weeklyTopPayload,
	})
}

func (s *Server) reorderRankingView(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	operator, ok := s.requireAdminRoleManager(w, r)
	if !ok {
		return
	}
	var input struct {
		Tab           string   `json:"tab"`
		Category      string   `json:"category"`
		Mode          string   `json:"mode"`
		OrderedToyIDs []string `json:"ordered_toy_ids"`
		Version       int64    `json:"version"`
	}
	if err := decodeJSON(r, &input); err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_BODY", Message: "请求体格式错误"})
		return
	}
	tabKey, categoryKey, valid := normalizeRankingViewKeys(input.Tab, input.Category)
	if !valid {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_RANKING_VIEW", Message: "榜单视图参数无效"})
		return
	}
	input.Mode = strings.ToUpper(strings.TrimSpace(input.Mode))
	if input.Mode != "AUTO" && input.Mode != "MANUAL" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_RANKING_VIEW_MODE", Message: "排序方式必须是 AUTO 或 MANUAL"})
		return
	}
	if input.Version < 0 {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_RANKING_VIEW_VERSION", Message: "version 参数无效"})
		return
	}

	orderedIDs := make([]string, 0, len(input.OrderedToyIDs))
	seen := make(map[string]struct{}, len(input.OrderedToyIDs))
	for _, id := range input.OrderedToyIDs {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if _, dup := seen[id]; dup {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_RANKING_VIEW_ORDER", Message: "顺序中存在重复商品"})
			return
		}
		seen[id] = struct{}{}
		orderedIDs = append(orderedIDs, id)
	}
	if input.Mode == "MANUAL" && len(orderedIDs) == 0 {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_RANKING_VIEW_ORDER", Message: "人工排序需要提交完整顺序"})
		return
	}

	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var advisoryLock any
	if err := tx.QueryRowContext(r.Context(), rankingViewOrderLock).Scan(&advisoryLock); err != nil {
		writeInternalError(w, r, err)
		return
	}
	current, err := loadRankingViewSettings(r.Context(), tx, tabKey, categoryKey)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if input.Version != current.Version {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusConflict, Code: "RANKING_VIEW_ORDER_STALE", Message: "榜单排序已被其他管理员修改，请刷新后重试"})
		return
	}

	if input.Mode == "MANUAL" {
		// 归属校验：提交的顺序必须是当前视图商品的子集（允许只排部分商品，
		// 未覆盖的新品按源榜单顺序追加）。细分榜以源快照视图为准，综合榜
		// 则是全部 active 商品；否则会产生永远不会展示的幽灵人工排序记录。
		var membershipQuery string
		var membershipArgs []any
		if tabKey != "" || categoryKey != "" {
			membershipQuery = `SELECT COUNT(*) FROM ranking_toy_rankings
				WHERE source_provider = 'beiyoujiang' AND tab_key = $1 AND category_key = $2 AND toy_id IN (`
			membershipArgs = append(membershipArgs, tabKey, categoryKey)
		} else {
			membershipQuery = `SELECT COUNT(*) FROM ranking_toys WHERE active = true AND id IN (`
		}
		placeholders := make([]string, 0, len(orderedIDs))
		base := len(membershipArgs)
		for i, id := range orderedIDs {
			// IN 列表里的纯参数无法从左侧列推断类型（多元素会转成
			// ANY(ARRAY[...])），Parse 阶段直接 42P18，必须显式标注。
			placeholders = append(placeholders, fmt.Sprintf("$%d::text", base+i+1))
			membershipArgs = append(membershipArgs, id)
		}
		membershipQuery += strings.Join(placeholders, ",") + ")"
		var memberCount int
		if err := tx.QueryRowContext(r.Context(), membershipQuery, membershipArgs...).Scan(&memberCount); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if memberCount != len(orderedIDs) {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusConflict, Code: "RANKING_VIEW_ORDER_STALE", Message: "部分商品不属于当前榜单视图，请刷新后重试"})
			return
		}
	}
	if _, err := tx.ExecContext(r.Context(), `DELETE FROM ranking_manual_orders WHERE tab_key = $1 AND category_key = $2`, tabKey, categoryKey); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if input.Mode == "MANUAL" {
		values := make([]string, 0, len(orderedIDs))
		args := []any{tabKey, categoryKey}
		for i, id := range orderedIDs {
			values = append(values, fmt.Sprintf("($1, $2, $%d::text, $%d::integer)", i+3, i+3+len(orderedIDs)))
			args = append(args, id)
		}
		for i := range orderedIDs {
			args = append(args, i+1)
		}
		query := `INSERT INTO ranking_manual_orders (tab_key, category_key, toy_id, position) VALUES ` + strings.Join(values, ", ")
		if _, err := tx.ExecContext(r.Context(), query, args...); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}

	var newVersion int64
	if err := tx.QueryRowContext(r.Context(), `
		INSERT INTO ranking_view_settings (tab_key, category_key, sort_mode, version, updated_by)
		VALUES ($1, $2, $3, 1, $4)
		ON CONFLICT (tab_key, category_key) DO UPDATE
		SET sort_mode = EXCLUDED.sort_mode, version = ranking_view_settings.version + 1,
		    updated_by = EXCLUDED.updated_by, updated_at = now()
		RETURNING version`, tabKey, categoryKey, input.Mode, operator.ID).Scan(&newVersion); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := appendAdminLogTx(r.Context(), tx, operator.ID, "ranking_view.reorder", "ranking_view", tabKey+"|"+categoryKey, "", requestIDFromRequest(r), httpserver.ClientIP(r), map[string]any{
		"tab": tabKey, "category": categoryKey, "mode": input.Mode,
		"count": len(orderedIDs), "version": newVersion,
	}, time.Now().UTC()); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"success": true,
		"mode":    input.Mode,
		"version": newVersion,
		"updated": len(orderedIDs),
	})
}
