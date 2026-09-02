package api

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/httpserver"
)

var (
	ErrRankingToyNotFound     = errors.New("ranking toy not found")
	ErrInvalidRankingRating   = errors.New("invalid ranking rating")
	ErrInvalidRankingComment  = errors.New("invalid ranking comment")
	ErrRankingCommentNotFound = errors.New("ranking comment not found")
)

type rankingToyRecord struct {
	ID               string
	Rank             int
	Name             string
	Merchant         string
	ReleaseYear      int
	Description      string
	Tags             []string
	AssetKey         string
	WantCount        int64
	RatingTotalCenti int64
	RatingCount      int64
	Category         string
	Segments         []string
	CoverMediaID     string
	HeroMediaID      string
	CoverObjectKey   string
	HeroObjectKey    string
	CouponURL        string
	SourceURL        string
	SourceProvider   string
	Wanted           bool
	Owned            bool
	Rating           sql.NullInt64
}

type rankingToyScanner interface {
	Scan(dest ...any) error
}

type rankingToyComment struct {
	ID             string
	AuthorID       string
	Username       string
	Nickname       string
	AvatarURL      string
	Level          int
	Content        string
	LikeCount      int64
	ViewerHasLiked bool
	CreatedAt      time.Time
	RootID         sql.NullString
	ParentID       sql.NullString
	ReplyToUserID  sql.NullString
	ReplyToUser    *userSummary
	ReplyCount     int64
	AuthorRating   sql.NullInt64
	Media          []rankingToyCommentMedia
}

// rankingToyCommentMedia 是本项目媒体库中的评价配图。导入任务只保存对象键，
// API 统一通过 publicMediaURL 组装访问地址，避免把源站 URL 暴露给客户端。
type rankingToyCommentMedia struct {
	ID       string `json:"id"`
	URL      string `json:"url"`
	Width    int    `json:"width"`
	Height   int    `json:"height"`
	MimeType string `json:"mime_type"`
}

type rankingToyCommentMediaPayload struct {
	ID          string `json:"id"`
	ObjectKey   string `json:"object_key"`
	Width       int    `json:"width"`
	Height      int    `json:"height"`
	MimeType    string `json:"mime_type"`
	HasVariants bool   `json:"has_variants"`
}

func parseRankingToyCommentMedia(raw []byte) ([]rankingToyCommentMedia, error) {
	if len(raw) == 0 {
		return []rankingToyCommentMedia{}, nil
	}
	var payload []rankingToyCommentMediaPayload
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, err
	}
	items := make([]rankingToyCommentMedia, 0, len(payload))
	for _, item := range payload {
		// has_variants 为假（backfill 未覆盖）时保留 objectKey 形态兜底；
		// 一旦派生变体就绪，URL 必须改走受控网关形态。
		url := publicMediaURL(item.ObjectKey)
		if item.HasVariants {
			url = gatewayMediaURL(item.ID, "detail")
		}
		items = append(items, rankingToyCommentMedia{
			ID: item.ID, URL: url, Width: item.Width,
			Height: item.Height, MimeType: item.MimeType,
		})
	}
	return items, nil
}

const rankingToyCommentMediaSelect = `COALESCE((
	SELECT json_agg(json_build_object(
		'id', media.id, 'object_key', media.object_key, 'width', media.width,
		'height', media.height, 'mime_type', media.mime_type,
		'has_variants', EXISTS (
			SELECT 1 FROM media_variants mv
			WHERE mv.media_id = media.id AND mv.status = 'ready'
			  AND mv.variant IN ('original', 'detail', 'thumb')
		)
	) ORDER BY links.sort_order ASC, media.id ASC)
	FROM ranking_toy_comment_media links
	JOIN media_assets media ON media.id = links.media_id
	WHERE links.comment_id = c.id AND media.status = 'ready' AND media.deleted_at IS NULL
), '[]'::json)`

// rankingToyCommentAvatarSelect 取评论作者头像的媒体 ID 与对象键；与作者
// 资料一起 JOIN，空键表示该作者未设置头像。
const rankingToyCommentAvatarSelect = `COALESCE(am.id, ''), COALESCE(am.object_key, '')`

func scanRankingToyCommentAvatar(item *rankingToyComment, avatarMediaID, avatarKey string) {
	item.AvatarURL = mediaVariantURL(avatarMediaID, avatarKey, "thumb")
}

func (s *Server) listRankingToys(w http.ResponseWriter, r *http.Request) {
	if !s.requireDatabase(w, r) {
		return
	}
	viewerID := ""
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		viewerID = viewer.ID
	}
	tabKey := strings.TrimSpace(r.URL.Query().Get("tab"))
	categoryKey := strings.TrimSpace(r.URL.Query().Get("category"))
	var rows *sql.Rows
	var err error
	if tabKey != "" || categoryKey != "" {
		// 标签榜在源站默认回落到飞机杯；这里和同步快照保持同一规则。
		if tabKey != "" && categoryKey == "" {
			categoryKey = "CUP"
		}
		// 展示排序 = 人工覆盖层（ranking_manual_orders，仅管理员可写）优先，
		// 未覆盖的商品回落到源榜单 rank；源排名本身永不修改，外部同步不会冲掉人工顺序。
		rows, err = s.db.QueryContext(r.Context(), `
		SELECT `+rankingToyColumns("source_rank.rank")+`
		FROM ranking_toy_rankings source_rank
		JOIN ranking_toys t ON t.id = source_rank.toy_id
		LEFT JOIN ranking_toy_user_states us
		  ON us.toy_id = t.id AND us.user_id = $1
		LEFT JOIN ranking_manual_orders mo
		  ON mo.toy_id = t.id AND mo.tab_key = $2 AND mo.category_key = $3
		LEFT JOIN media_assets cover ON cover.id = t.cover_media_id AND cover.status = 'ready' AND cover.deleted_at IS NULL
		LEFT JOIN media_assets hero ON hero.id = t.hero_media_id AND hero.status = 'ready' AND hero.deleted_at IS NULL
		WHERE source_rank.source_provider = 'beiyoujiang'
		  AND source_rank.tab_key = $2 AND source_rank.category_key = $3
		  AND t.active = true
		ORDER BY mo.position ASC NULLS LAST, source_rank.rank ASC, t.id ASC`, viewerID, tabKey, categoryKey)
	} else {
		// 综合热榜视图键为 tab/category 双空，与细分榜共用同一覆盖层。
		rows, err = s.db.QueryContext(r.Context(), `
		SELECT `+rankingToyColumns("t.rank")+`
		FROM ranking_toys t
		LEFT JOIN ranking_toy_user_states us
		  ON us.toy_id = t.id AND us.user_id = $1
		LEFT JOIN ranking_manual_orders mo
		  ON mo.toy_id = t.id AND mo.tab_key = '' AND mo.category_key = ''
		LEFT JOIN media_assets cover ON cover.id = t.cover_media_id AND cover.status = 'ready' AND cover.deleted_at IS NULL
		LEFT JOIN media_assets hero ON hero.id = t.hero_media_id AND hero.status = 'ready' AND hero.deleted_at IS NULL
		WHERE t.active = true
		ORDER BY mo.position ASC NULLS LAST, t.rank ASC, t.id ASC`, viewerID)
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		item, scanErr := scanRankingToy(rows)
		if scanErr != nil {
			writeInternalError(w, r, scanErr)
			return
		}
		items = append(items, item.response())
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	response := map[string]any{"items": items}
	if weeklyTop := s.loadWeeklyTopToy(r.Context(), viewerID, tabKey, categoryKey); weeklyTop != nil {
		response["weekly_top"] = weeklyTop.response()
	}
	httpserver.WriteJSON(w, http.StatusOK, response)
}

// loadWeeklyTopToy 返回视图在源站的置顶主推位；综合热榜视图的键为
// tab/category 双空，与快照保持一致。
func (s *Server) loadWeeklyTopToy(ctx context.Context, viewerID, tabKey, categoryKey string) *rankingToyRecord {
	var toyID string
	err := s.db.QueryRowContext(ctx, `
		SELECT t.id
		FROM ranking_toy_rankings source_rank
		JOIN ranking_toys t ON t.id = source_rank.toy_id
		WHERE source_rank.source_provider = 'beiyoujiang'
		  AND source_rank.tab_key = $1 AND source_rank.category_key = $2
		  AND source_rank.is_weekly_top = true
		  AND t.active = true
		ORDER BY source_rank.rank ASC
		LIMIT 1`, tabKey, categoryKey).Scan(&toyID)
	if err != nil {
		return nil
	}
	item, err := s.loadRankingToy(ctx, toyID, viewerID)
	if err != nil {
		return nil
	}
	return &item
}

func (s *Server) getRankingToy(w http.ResponseWriter, r *http.Request, toyID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	viewerID := ""
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		viewerID = viewer.ID
	}
	item, err := s.loadRankingToy(r.Context(), toyID, viewerID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrRankingToyNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	sort := r.URL.Query().Get("comment_sort")
	if sort == "" {
		sort = "weight"
	}
	if sort != "weight" && sort != "latest" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_COMMENT_SORT", Message: "评论排序参数无效"})
		return
	}
	comments, err := s.listRankingToyCommentsPage(r.Context(), toyID, viewerID, sort, nil, 20)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	ratingDistribution := map[string]int{
		"1": 0, "2": 0, "3": 0, "4": 0, "5": 0,
		"6": 0, "7": 0, "8": 0, "9": 0, "10": 0,
	}
	distRows, distErr := s.db.QueryContext(r.Context(), `
		SELECT score, rating_count
		FROM ranking_toy_rating_distribution
		WHERE toy_id = $1 AND score >= 1 AND score <= 10
		ORDER BY score`, toyID)
	if distErr != nil {
		writeInternalError(w, r, distErr)
		return
	}
	defer distRows.Close()
	for distRows.Next() {
		var score int
		var count int
		if scanErr := distRows.Scan(&score, &count); scanErr != nil {
			writeInternalError(w, r, scanErr)
			return
		}
		ratingDistribution[strconv.Itoa(score)] = count
	}
	if err := distRows.Err(); err != nil {
		writeInternalError(w, r, err)
		return
	}

	response := item.response()
	response["comments"] = comments.Items
	response["comment_sort"] = sort
	response["comments_next_cursor"] = comments.NextCursor
	response["comments_has_more"] = comments.HasMore
	response["rating_distribution"] = ratingDistribution
	httpserver.WriteJSON(w, http.StatusOK, response)
}

func (s *Server) loadRankingToy(ctx context.Context, toyID, viewerID string) (rankingToyRecord, error) {
	return scanRankingToy(s.db.QueryRowContext(ctx, `
		SELECT `+rankingToyColumns("t.rank")+`
		FROM ranking_toys t
		LEFT JOIN ranking_toy_user_states us
		  ON us.toy_id = t.id AND us.user_id = $2
		LEFT JOIN media_assets cover ON cover.id = t.cover_media_id AND cover.status = 'ready' AND cover.deleted_at IS NULL
		LEFT JOIN media_assets hero ON hero.id = t.hero_media_id AND hero.status = 'ready' AND hero.deleted_at IS NULL
		WHERE t.id = $1 AND t.active = true`, toyID, viewerID))
}

// rankingToyColumns 由两条受控查询共用。rankExpression 仅传入源码常量，
// 不接受用户输入，避免为了支持视图名次引入 SQL 拼接风险。
func rankingToyColumns(rankExpression string) string {
	return `t.id, ` + rankExpression + `, t.name, t.merchant, t.release_year, t.description,
		array_to_json(t.tags), t.asset_key, t.want_count,
		t.rating_total_centi, t.rating_count,
		t.category, array_to_json(t.segments),
		COALESCE(cover.id, ''), COALESCE(cover.object_key, ''),
		COALESCE(hero.id, ''), COALESCE(hero.object_key, ''),
		t.coupon_url, t.source_url, t.source_provider,
		COALESCE(us.wanted, false), COALESCE(us.owned, false), us.rating`
}

func scanRankingToy(scanner rankingToyScanner) (rankingToyRecord, error) {
	var item rankingToyRecord
	var tagsRaw []byte
	var segmentsRaw []byte
	if err := scanner.Scan(
		&item.ID,
		&item.Rank,
		&item.Name,
		&item.Merchant,
		&item.ReleaseYear,
		&item.Description,
		&tagsRaw,
		&item.AssetKey,
		&item.WantCount,
		&item.RatingTotalCenti,
		&item.RatingCount,
		&item.Category,
		&segmentsRaw,
		&item.CoverMediaID,
		&item.CoverObjectKey,
		&item.HeroMediaID,
		&item.HeroObjectKey,
		&item.CouponURL,
		&item.SourceURL,
		&item.SourceProvider,
		&item.Wanted,
		&item.Owned,
		&item.Rating,
	); err != nil {
		return rankingToyRecord{}, err
	}
	if len(tagsRaw) > 0 {
		if err := json.Unmarshal(tagsRaw, &item.Tags); err != nil {
			return rankingToyRecord{}, err
		}
	}
	if item.Tags == nil {
		item.Tags = []string{}
	}
	if len(segmentsRaw) > 0 {
		if err := json.Unmarshal(segmentsRaw, &item.Segments); err != nil {
			return rankingToyRecord{}, err
		}
	}
	if item.Segments == nil {
		item.Segments = []string{}
	}
	return item, nil
}

func (item rankingToyRecord) response() map[string]any {
	return map[string]any{
		"id":           item.ID,
		"rank":         item.Rank,
		"name":         item.Name,
		"merchant":     item.Merchant,
		"release_year": item.ReleaseYear,
		"description":  item.Description,
		"tags":         item.Tags,
		"asset_key":    item.AssetKey,
		"cover_url":    mediaVariantURL(item.CoverMediaID, item.CoverObjectKey, "detail"),
		"hero_url":     mediaVariantURL(item.HeroMediaID, item.HeroObjectKey, "detail"),
		"coupon_url":   item.CouponURL,
		"source_url":   item.SourceURL,
		"source":       item.SourceProvider,
		"want_count":   item.WantCount,
		"rating_count": item.RatingCount,
		"category":     item.Category,
		"segments":     item.Segments,
		"score":        item.score(),
		"viewer_state": map[string]any{
			"wanted": item.Wanted,
			"owned":  item.Owned,
			"rating": nullableInt(item.Rating),
		},
	}
}

// mediaURLOrEmpty 对未配置封面的商品返回空串，而不是把对象存储根地址
// 当成图片地址下发给客户端。
func mediaURLOrEmpty(objectKey string) string {
	if strings.TrimSpace(objectKey) == "" {
		return ""
	}
	return publicMediaURL(objectKey)
}

func (item rankingToyRecord) score() float64 {
	if item.RatingCount == 0 {
		return 0
	}
	return math.Round(float64(item.RatingTotalCenti)/float64(item.RatingCount)/10) / 10
}

func nullableInt(value sql.NullInt64) any {
	if !value.Valid {
		return nil
	}
	return value.Int64
}

type rankingToyCommentPage struct {
	Items      []map[string]any
	NextCursor any
	HasMore    bool
}

type rankingToyCommentCursor struct {
	Sort      string    `json:"sort"`
	LikeCount int64     `json:"like_count,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	ID        string    `json:"id"`
}

func (s *Server) listRankingToyComments(w http.ResponseWriter, r *http.Request, toyID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	sort := r.URL.Query().Get("sort")
	if sort == "" {
		sort = "weight"
	}
	if sort != "weight" && sort != "latest" {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_COMMENT_SORT", Message: "评论排序参数无效"})
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	var exists string
	if err := s.db.QueryRowContext(r.Context(), `SELECT id FROM ranking_toys WHERE id = $1 AND active = true`, toyID).Scan(&exists); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrRankingToyNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var cursor *rankingToyCommentCursor
	if value := r.URL.Query().Get("cursor"); value != "" {
		decoded, decodeErr := decodeRankingToyCommentCursor(value)
		if decodeErr != nil || decoded.Sort != sort {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		cursor = &decoded
	}
	viewerID := ""
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		viewerID = viewer.ID
	}
	page, err := s.listRankingToyCommentsPage(r.Context(), toyID, viewerID, sort, cursor, limit)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"items":       page.Items,
		"next_cursor": page.NextCursor,
		"has_more":    page.HasMore,
	})
}

func (s *Server) listRankingToyCommentsPage(ctx context.Context, toyID, viewerID, sort string, cursor *rankingToyCommentCursor, limit int) (rankingToyCommentPage, error) {
	orderBy := "c.like_count DESC, c.created_at DESC, c.id DESC"
	if sort == "latest" {
		orderBy = "c.created_at DESC, c.id DESC"
	}
	query := `SELECT c.id, c.author_id, u.username, COALESCE(up.nickname, u.username),
	                 COALESCE(up.level, 1), c.content, c.like_count,
	                 EXISTS (SELECT 1 FROM ranking_toy_comment_likes l WHERE l.comment_id = c.id AND l.user_id = $2),
	                 c.created_at, c.root_id, c.parent_id, c.reply_to_user_id, c.reply_count,
	                 aus.rating, ` + rankingToyCommentMediaSelect + `, ` + rankingToyCommentAvatarSelect + `
	          FROM ranking_toy_comments c
	          JOIN users u ON u.id = c.author_id
	          LEFT JOIN user_profiles up ON up.user_id = c.author_id
	          LEFT JOIN media_assets am ON am.id = up.avatar_media_id
	          LEFT JOIN ranking_toy_user_states aus ON aus.toy_id = c.toy_id AND aus.user_id = c.author_id
		          WHERE c.toy_id = $1 AND c.deleted_at IS NULL AND c.parent_id IS NULL`
	args := []any{toyID, viewerID}
	if cursor != nil {
		if sort == "latest" {
			query += " AND (c.created_at, c.id) < ($3, $4)"
			args = append(args, cursor.CreatedAt, cursor.ID)
		} else {
			query += " AND (c.like_count, c.created_at, c.id) < ($3, $4, $5)"
			args = append(args, cursor.LikeCount, cursor.CreatedAt, cursor.ID)
		}
	}
	limitPosition := len(args) + 1
	query += " ORDER BY " + orderBy + fmt.Sprintf(" LIMIT $%d", limitPosition)
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return rankingToyCommentPage{}, err
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	var last rankingToyComment
	for rows.Next() {
		var item rankingToyComment
		var mediaRaw []byte
		var avatarMediaID, avatarKey string
		if err := rows.Scan(
			&item.ID,
			&item.AuthorID,
			&item.Username,
			&item.Nickname,
			&item.Level,
			&item.Content,
			&item.LikeCount,
			&item.ViewerHasLiked,
			&item.CreatedAt,
			&item.RootID,
			&item.ParentID,
			&item.ReplyToUserID,
			&item.ReplyCount,
			&item.AuthorRating,
			&mediaRaw,
			&avatarMediaID,
			&avatarKey,
		); err != nil {
			return rankingToyCommentPage{}, err
		}
		scanRankingToyCommentAvatar(&item, avatarMediaID, avatarKey)
		item.Media, err = parseRankingToyCommentMedia(mediaRaw)
		if err != nil {
			return rankingToyCommentPage{}, err
		}
		if item.ReplyToUserID.Valid && item.ReplyToUserID.String != "" {
			item.ReplyToUser, err = loadUserSummary(ctx, s.db, item.ReplyToUserID.String)
			if err != nil {
				return rankingToyCommentPage{}, err
			}
		}
		if len(items) < limit {
			last = item
		}
		items = append(items, item.response())
	}
	if err := rows.Err(); err != nil {
		return rankingToyCommentPage{}, err
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	var nextCursor any
	if hasMore && len(items) > 0 {
		encoded, err := encodeRankingToyCommentCursor(rankingToyCommentCursor{
			Sort: sort, LikeCount: last.LikeCount, CreatedAt: last.CreatedAt, ID: last.ID,
		})
		if err != nil {
			return rankingToyCommentPage{}, err
		}
		nextCursor = encoded
	}
	return rankingToyCommentPage{Items: items, NextCursor: nextCursor, HasMore: hasMore}, nil
}

func (s *Server) listRankingToyReplies(w http.ResponseWriter, r *http.Request, commentID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	limit, err := parseLimit(r.URL.Query().Get("limit"))
	if err != nil {
		httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_LIMIT", Message: "limit 必须是 1 到 50 之间的整数"})
		return
	}
	var toyID, rootID string
	err = s.db.QueryRowContext(r.Context(), `
		SELECT toy_id, COALESCE(root_id, id)
		FROM ranking_toy_comments
		WHERE id = $1 AND deleted_at IS NULL`, commentID).Scan(&toyID, &rootID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrRankingCommentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	var cursor *rankingToyCommentCursor
	if value := r.URL.Query().Get("cursor"); value != "" {
		decoded, decodeErr := decodeRankingToyCommentCursor(value)
		if decodeErr != nil || decoded.Sort != "replies" {
			httpserver.WriteAppError(w, r, httpserver.AppError{Status: http.StatusBadRequest, Code: "INVALID_CURSOR", Message: "cursor 无效"})
			return
		}
		cursor = &decoded
	}
	viewerID := ""
	if viewer, ok := s.optionalAuthenticatedUser(r.Context(), r); ok {
		viewerID = viewer.ID
	}
	page, err := s.listRankingToyRepliesPage(r.Context(), toyID, rootID, viewerID, cursor, limit)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{
		"items":       page.Items,
		"next_cursor": page.NextCursor,
		"has_more":    page.HasMore,
	})
}

func (s *Server) listRankingToyRepliesPage(ctx context.Context, toyID, rootID, viewerID string, cursor *rankingToyCommentCursor, limit int) (rankingToyCommentPage, error) {
	query := `SELECT c.id, c.author_id, u.username, COALESCE(up.nickname, u.username),
	                 COALESCE(up.level, 1), c.content, c.like_count,
	                 EXISTS (SELECT 1 FROM ranking_toy_comment_likes l WHERE l.comment_id = c.id AND l.user_id = $3),
	                 c.created_at, c.root_id, c.parent_id, c.reply_to_user_id, c.reply_count,
	                 aus.rating, ` + rankingToyCommentMediaSelect + `, ` + rankingToyCommentAvatarSelect + `
	          FROM ranking_toy_comments c
	          JOIN users u ON u.id = c.author_id
	          LEFT JOIN user_profiles up ON up.user_id = c.author_id
	          LEFT JOIN media_assets am ON am.id = up.avatar_media_id
	          LEFT JOIN ranking_toy_user_states aus ON aus.toy_id = c.toy_id AND aus.user_id = c.author_id
	          WHERE c.toy_id = $1 AND COALESCE(c.root_id, c.id) = $2 AND c.id <> $2 AND c.deleted_at IS NULL`
	args := []any{toyID, rootID, viewerID}
	if cursor != nil {
		query += " AND (c.created_at, c.id) > ($4, $5)"
		args = append(args, cursor.CreatedAt, cursor.ID)
	}
	limitPosition := len(args) + 1
	query += fmt.Sprintf(" ORDER BY c.created_at ASC, c.id ASC LIMIT $%d", limitPosition)
	args = append(args, limit+1)
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return rankingToyCommentPage{}, err
	}
	defer rows.Close()
	items := make([]map[string]any, 0, limit+1)
	var last rankingToyComment
	for rows.Next() {
		var item rankingToyComment
		var mediaRaw []byte
		var avatarMediaID, avatarKey string
		if err := rows.Scan(
			&item.ID, &item.AuthorID, &item.Username, &item.Nickname, &item.Level,
			&item.Content, &item.LikeCount, &item.ViewerHasLiked, &item.CreatedAt,
			&item.RootID, &item.ParentID, &item.ReplyToUserID, &item.ReplyCount,
			&item.AuthorRating,
			&mediaRaw,
			&avatarMediaID,
			&avatarKey,
		); err != nil {
			return rankingToyCommentPage{}, err
		}
		scanRankingToyCommentAvatar(&item, avatarMediaID, avatarKey)
		item.Media, err = parseRankingToyCommentMedia(mediaRaw)
		if err != nil {
			return rankingToyCommentPage{}, err
		}
		if item.ReplyToUserID.Valid && item.ReplyToUserID.String != "" {
			item.ReplyToUser, err = loadUserSummary(ctx, s.db, item.ReplyToUserID.String)
			if err != nil {
				return rankingToyCommentPage{}, err
			}
		}
		if len(items) < limit {
			last = item
		}
		items = append(items, item.response())
	}
	if err := rows.Err(); err != nil {
		return rankingToyCommentPage{}, err
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	var nextCursor any
	if hasMore && len(items) > 0 {
		encoded, err := encodeRankingToyCommentCursor(rankingToyCommentCursor{
			Sort: "replies", CreatedAt: last.CreatedAt, ID: last.ID,
		})
		if err != nil {
			return rankingToyCommentPage{}, err
		}
		nextCursor = encoded
	}
	return rankingToyCommentPage{Items: items, NextCursor: nextCursor, HasMore: hasMore}, nil
}

func (item rankingToyComment) response() map[string]any {
	response := map[string]any{
		"id":               item.ID,
		"content":          item.Content,
		"like_count":       item.LikeCount,
		"root_id":          rankingNullableString(item.RootID),
		"parent_id":        rankingNullableString(item.ParentID),
		"reply_to_user_id": rankingNullableString(item.ReplyToUserID),
		"reply_count":      item.ReplyCount,
		"created_at":       item.CreatedAt,
		"author_rating":    nullableInt(item.AuthorRating),
		"media":            item.Media,
		"author": map[string]any{
			"id":            item.AuthorID,
			"username":      item.Username,
			"nickname":      item.Nickname,
			"level":         item.Level,
			"author_rating": nullableInt(item.AuthorRating),
			"avatar_url":    item.AvatarURL,
		},
		"viewer_state": map[string]any{"has_liked": item.ViewerHasLiked},
	}
	if item.ReplyToUser != nil {
		response["reply_to_user"] = item.ReplyToUser
	}
	return response
}

func rankingNullableString(value sql.NullString) any {
	if !value.Valid || value.String == "" {
		return nil
	}
	return value.String
}

func (s *Server) setRankingToyFlag(w http.ResponseWriter, r *http.Request, toyID, field string, active bool) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.requireCapability(w, r, user, capVote) {
		return
	}
	if field != "wanted" && field != "owned" {
		writeInternalError(w, r, ErrInvalidRankingComment)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if err := lockRankingToy(r, tx, toyID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	previous := false
	stateErr := tx.QueryRowContext(r.Context(), `SELECT `+field+` FROM ranking_toy_user_states WHERE toy_id = $1 AND user_id = $2`, toyID, user.ID).Scan(&previous)
	if errors.Is(stateErr, sql.ErrNoRows) {
		stateErr = nil
	}
	if stateErr != nil {
		writeInternalError(w, r, stateErr)
		return
	}
	query := `INSERT INTO ranking_toy_user_states (toy_id, user_id, ` + field + `)
		VALUES ($1, $2, $3)
		ON CONFLICT (toy_id, user_id) DO UPDATE SET ` + field + ` = EXCLUDED.` + field + `, updated_at = now()`
	if _, err := tx.ExecContext(r.Context(), query, toyID, user.ID, active); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if field == "wanted" && previous != active {
		delta := 1
		if !active {
			delta = -1
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toys SET want_count = GREATEST(want_count + $2, 0), updated_at = now() WHERE id = $1`, toyID, delta); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	var count int64
	countQuery := `SELECT count(*) FROM ranking_toy_user_states WHERE toy_id = $1 AND ` + field + ` = true`
	if field == "wanted" {
		countQuery = `SELECT want_count FROM ranking_toys WHERE id = $1`
	}
	if err := tx.QueryRowContext(r.Context(), countQuery, toyID).Scan(&count); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active, "count": count})
}

func lockRankingToy(r *http.Request, tx *sql.Tx, toyID string) error {
	var id string
	err := tx.QueryRowContext(r.Context(), `SELECT id FROM ranking_toys WHERE id = $1 AND active = true FOR UPDATE`, toyID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrRankingToyNotFound
	}
	return err
}

func (s *Server) rateRankingToy(w http.ResponseWriter, r *http.Request, toyID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.requireCapability(w, r, user, capVote) {
		return
	}
	var input struct {
		Score int `json:"score"`
	}
	if err := decodeJSON(r, &input); err != nil || input.Score < 1 || input.Score > 10 {
		writeAuthError(w, r, ErrInvalidRankingRating)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if err := lockRankingToy(r, tx, toyID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	var previous sql.NullInt64
	err = tx.QueryRowContext(r.Context(), `SELECT rating FROM ranking_toy_user_states WHERE toy_id = $1 AND user_id = $2 FOR UPDATE`, toyID, user.ID).Scan(&previous)
	if errors.Is(err, sql.ErrNoRows) {
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO ranking_toy_user_states (toy_id, user_id, rating) VALUES ($1, $2, $3)`, toyID, user.ID, input.Score); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toys SET rating_total_centi = rating_total_centi + $2, rating_count = rating_count + 1, updated_at = now() WHERE id = $1`, toyID, input.Score*100); err != nil {
			writeInternalError(w, r, err)
			return
		}
		if err := adjustRankingToyRatingDistribution(r.Context(), tx, toyID, input.Score, 1); err != nil {
			writeInternalError(w, r, err)
			return
		}
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	} else {
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toy_user_states SET rating = $3, updated_at = now() WHERE toy_id = $1 AND user_id = $2`, toyID, user.ID, input.Score); err != nil {
			writeInternalError(w, r, err)
			return
		}
		previousValue := int(previous.Int64)
		if !previous.Valid {
			if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toys SET rating_total_centi = rating_total_centi + $2, rating_count = rating_count + 1, updated_at = now() WHERE id = $1`, toyID, input.Score*100); err != nil {
				writeInternalError(w, r, err)
				return
			}
			if err := adjustRankingToyRatingDistribution(r.Context(), tx, toyID, input.Score, 1); err != nil {
				writeInternalError(w, r, err)
				return
			}
		} else if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toys SET rating_total_centi = GREATEST(rating_total_centi + $2, 0), updated_at = now() WHERE id = $1`, toyID, (input.Score-previousValue)*100); err != nil {
			writeInternalError(w, r, err)
			return
		} else if previousValue != input.Score {
			if err := adjustRankingToyRatingDistribution(r.Context(), tx, toyID, previousValue, -1); err != nil {
				writeInternalError(w, r, err)
				return
			}
			if err := adjustRankingToyRatingDistribution(r.Context(), tx, toyID, input.Score, 1); err != nil {
				writeInternalError(w, r, err)
				return
			}
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	item, err := s.loadRankingToy(r.Context(), toyID, user.ID)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, item.response())
}

func adjustRankingToyRatingDistribution(ctx context.Context, tx *sql.Tx, toyID string, score int, delta int64) error {
	if delta == 0 {
		return nil
	}
	_, err := tx.ExecContext(ctx, `
		INSERT INTO ranking_toy_rating_distribution (toy_id, score, rating_count)
		VALUES ($1, $2, $3)
		ON CONFLICT (toy_id, score) DO UPDATE
		SET rating_count = GREATEST(ranking_toy_rating_distribution.rating_count + EXCLUDED.rating_count, 0)`,
		toyID, score, delta,
	)
	return err
}

func (s *Server) createRankingToyComment(w http.ResponseWriter, r *http.Request, toyID string) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.requireCapability(w, r, user, capComment) {
		return
	}
	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if idempotencyKey == "" || len(idempotencyKey) > 128 {
		writeAuthError(w, r, ErrIdempotencyKeyRequired)
		return
	}
	var input struct {
		Content       string `json:"content"`
		ParentID      string `json:"parent_id"`
		ReplyToUserID string `json:"reply_to_user_id"`
	}
	if err := decodeJSON(r, &input); err != nil {
		writeAuthError(w, r, ErrInvalidRankingComment)
		return
	}
	input.Content = strings.TrimSpace(input.Content)
	if input.Content == "" || len([]rune(input.Content)) > 5000 {
		writeAuthError(w, r, ErrInvalidRankingComment)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	if err := lockRankingToy(r, tx, toyID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	parentID := strings.TrimSpace(input.ParentID)
	replyToUserID := strings.TrimSpace(input.ReplyToUserID)
	rootID := ""
	if parentID != "" {
		var parentToyID string
		var parentRootID sql.NullString
		err := tx.QueryRowContext(r.Context(), `
			SELECT toy_id, root_id FROM ranking_toy_comments
			WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`, parentID).Scan(&parentToyID, &parentRootID)
		if errors.Is(err, sql.ErrNoRows) {
			writeAuthError(w, r, ErrRankingCommentNotFound)
			return
		}
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		if parentToyID != toyID {
			writeAuthError(w, r, ErrInvalidRankingComment)
			return
		}
		if parentRootID.Valid && parentRootID.String != "" {
			rootID = parentRootID.String
		} else {
			rootID = parentID
		}
	}
	commentID := newPostID()
	if rootID == "" {
		rootID = commentID
	}
	var insertedID string
	created := true
	err = tx.QueryRowContext(r.Context(), `
		INSERT INTO ranking_toy_comments (id, toy_id, author_id, content, idempotency_key, root_id, parent_id, reply_to_user_id)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''), NULLIF($8, ''))
		ON CONFLICT (author_id, idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING
		RETURNING id`, commentID, toyID, user.ID, input.Content, idempotencyKey, rootID, parentID, replyToUserID).Scan(&insertedID)
	if errors.Is(err, sql.ErrNoRows) {
		created = false
		if err := tx.QueryRowContext(r.Context(), `SELECT id FROM ranking_toy_comments WHERE author_id = $1 AND idempotency_key = $2`, user.ID, idempotencyKey).Scan(&insertedID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	if created && parentID != "" {
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toy_comments SET reply_count = reply_count + 1, updated_at = now() WHERE id = $1`, rootID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	comment, err := s.loadRankingToyComment(r, insertedID, user.ID)
	if errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrRankingCommentNotFound)
		return
	}
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusCreated, comment.response())
}

func (s *Server) loadRankingToyComment(r *http.Request, commentID, viewerID string) (rankingToyComment, error) {
	var item rankingToyComment
	var mediaRaw []byte
	var avatarMediaID, avatarKey string
	err := s.db.QueryRowContext(r.Context(), `
		SELECT c.id, c.author_id, u.username, COALESCE(up.nickname, u.username),
		       COALESCE(up.level, 1), c.content, c.like_count,
		       EXISTS (SELECT 1 FROM ranking_toy_comment_likes l WHERE l.comment_id = c.id AND l.user_id = $2),
		       c.created_at, c.root_id, c.parent_id, c.reply_to_user_id, c.reply_count,
		       aus.rating, `+rankingToyCommentMediaSelect+`, `+rankingToyCommentAvatarSelect+`
		FROM ranking_toy_comments c
		JOIN users u ON u.id = c.author_id
		LEFT JOIN user_profiles up ON up.user_id = c.author_id
		LEFT JOIN media_assets am ON am.id = up.avatar_media_id
		LEFT JOIN ranking_toy_user_states aus ON aus.toy_id = c.toy_id AND aus.user_id = c.author_id
		WHERE c.id = $1 AND c.deleted_at IS NULL`, commentID, viewerID).Scan(
		&item.ID, &item.AuthorID, &item.Username, &item.Nickname, &item.Level,
		&item.Content, &item.LikeCount, &item.ViewerHasLiked, &item.CreatedAt,
		&item.RootID, &item.ParentID, &item.ReplyToUserID, &item.ReplyCount,
		&item.AuthorRating, &mediaRaw, &avatarMediaID, &avatarKey,
	)
	if err != nil {
		return item, err
	}
	scanRankingToyCommentAvatar(&item, avatarMediaID, avatarKey)
	item.Media, err = parseRankingToyCommentMedia(mediaRaw)
	if err != nil {
		return item, err
	}
	if item.ReplyToUserID.Valid && item.ReplyToUserID.String != "" {
		item.ReplyToUser, err = loadUserSummary(r.Context(), s.db, item.ReplyToUserID.String)
		if err != nil {
			return item, err
		}
	}
	return item, err
}

func (s *Server) toggleRankingToyCommentLike(w http.ResponseWriter, r *http.Request, commentID string, active bool) {
	if !s.requireDatabase(w, r) {
		return
	}
	user, ok := s.authenticatedUser(w, r)
	if !ok {
		return
	}
	if !s.requireCapability(w, r, user, capLike) {
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}
	defer tx.Rollback()
	var existingID string
	if err := tx.QueryRowContext(r.Context(), `SELECT id FROM ranking_toy_comments WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`, commentID).Scan(&existingID); errors.Is(err, sql.ErrNoRows) {
		writeAuthError(w, r, ErrRankingCommentNotFound)
		return
	} else if err != nil {
		writeInternalError(w, r, err)
		return
	}
	changed := false
	if active {
		result, err := tx.ExecContext(r.Context(), `INSERT INTO ranking_toy_comment_likes (comment_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, commentID, user.ID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		affected, err := result.RowsAffected()
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		changed = affected > 0
	} else {
		result, err := tx.ExecContext(r.Context(), `DELETE FROM ranking_toy_comment_likes WHERE comment_id = $1 AND user_id = $2`, commentID, user.ID)
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		affected, err := result.RowsAffected()
		if err != nil {
			writeInternalError(w, r, err)
			return
		}
		changed = affected > 0
	}
	if changed {
		operator := "+ 1"
		if !active {
			operator = "- 1"
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE ranking_toy_comments SET like_count = GREATEST(like_count `+operator+`, 0), updated_at = now() WHERE id = $1`, commentID); err != nil {
			writeInternalError(w, r, err)
			return
		}
	}
	var count int64
	if err := tx.QueryRowContext(r.Context(), `SELECT like_count FROM ranking_toy_comments WHERE id = $1`, commentID).Scan(&count); err != nil {
		writeInternalError(w, r, err)
		return
	}
	if err := tx.Commit(); err != nil {
		writeInternalError(w, r, err)
		return
	}
	httpserver.WriteJSON(w, http.StatusOK, map[string]any{"active": active, "like_count": count})
}

func encodeRankingToyCommentCursor(cursor rankingToyCommentCursor) (string, error) {
	data, err := json.Marshal(cursor)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func decodeRankingToyCommentCursor(value string) (rankingToyCommentCursor, error) {
	data, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return rankingToyCommentCursor{}, err
	}
	var cursor rankingToyCommentCursor
	if err := json.Unmarshal(data, &cursor); err != nil || cursor.Sort == "" || cursor.ID == "" || cursor.CreatedAt.IsZero() {
		return rankingToyCommentCursor{}, errors.New("invalid ranking comment cursor")
	}
	return cursor, nil
}
