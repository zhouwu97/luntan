// ranking-import 把杯友酱公开榜单快照导入本项目数据库。
//
// 数据来源：scripts/sync_beiyoujiang_rankings.ps1 生成的
// server/seeds/beiyoujiang_snapshot.json（榜单、评价、配图均已在
// 本地缓存）。导入器只负责幂等落库：
//   - ranking_toys + 按视图名次（ranking_toy_rankings）
//   - 封面/主图与评价配图 → media_assets + 对象存储
//   - 评价/回复 → ranking_toy_comments（合成用户作作者，含源站点赞基线）
//   - 想冲数、评分汇总、评分分布保留“源站基线 + 本站用户增量”
//
// 用法：MEDIA_STORAGE_DIR=... DATABASE_URL=... go run ./cmd/ranking-import \
//   -snapshot server/seeds/beiyoujiang_snapshot.json -assets-root .
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"log"
	"math"
	"mime"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/zhouwu97/luntan/server/internal/media"
	"github.com/zhouwu97/luntan/server/internal/platform/database"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)

const (
	sourceProvider     = "beiyoujiang"
	importerUserID     = "byj-importer"
	importerUsername   = "byj_importer"
	importerNickname   = "杯友酱同步"
	defaultObjectPrefix = "ranking/beiyoujiang/"
)

type snapshotToy struct {
	ID            int       `json:"id"`
	Name          string    `json:"name"`
	Merchant      string    `json:"merchant"`
	CoverURL      []string  `json:"coverUrl"`
	WeeklyTopImg  []string  `json:"weeklyTopImg"`
	ShopLink      string    `json:"shopLink"`
	Description   string    `json:"description"`
	Tags          string    `json:"tags"`
	ReleaseYear   int       `json:"releaseYear"`
	Stimulation   string    `json:"stimulation"`
	Category      string    `json:"category"`
	Rating        float64   `json:"rating"`
	ReviewCount   int       `json:"reviewCount"`
	WantCount     int64     `json:"wantCount"`
	UpdatedAt     time.Time `json:"updatedAt"`
	Rank          int       `json:"rank"`
	AssetPath     string    `json:"asset_path"`
	HeroAssetPath string    `json:"hero_asset_path"`
}

type snapshotView struct {
	WeeklyTop *snapshotToy   `json:"weekly_top"`
	Items     []snapshotToy  `json:"items"`
	Total     int            `json:"total"`
}

type snapshotReplyUser struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
	Level    int    `json:"level"`
}

type snapshotReply struct {
	ID          int64           `json:"id"`
	Content     string          `json:"content"`
	Username    string          `json:"username"`
	UserID      int64           `json:"userId"`
	ReplyToUser json.RawMessage `json:"replyToUser"`
	Level       int             `json:"level"`
}

// parseReplyToUser 兼容源站两种形态：完整用户对象（含 id）或纯用户名
// 字符串。纯用户名只能按本库已导入用户的昵称反查。
func (imp *importer) parseReplyToUser(ctx context.Context, raw json.RawMessage) (string, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return "", nil
	}
	var user snapshotReplyUser
	if err := json.Unmarshal(raw, &user); err == nil && user.ID > 0 {
		return fmt.Sprintf("byj-user-%d", user.ID), nil
	}
	var username string
	if err := json.Unmarshal(raw, &username); err != nil || strings.TrimSpace(username) == "" {
		return "", nil
	}
	var userID string
	err := imp.db.QueryRowContext(ctx, `
		SELECT up.user_id FROM user_profiles up
		JOIN users u ON u.id = up.user_id AND u.deleted_at IS NULL
		WHERE up.nickname = $1 AND up.user_id LIKE 'byj-user-%'
		ORDER BY up.user_id LIMIT 1`, username).Scan(&userID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return userID, err
}

type snapshotSourceUser struct {
	ID              int64  `json:"id"`
	Username        string `json:"username"`
	Level           int    `json:"level"`
	AvatarAssetPath string `json:"avatar_asset_path"`
}

type snapshotReviewUser struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
	Level    int    `json:"level"`
}

type snapshotReview struct {
	ID           int64              `json:"id"`
	Score        float64            `json:"score"`
	Content      string             `json:"content"`
	LikeCount    int64              `json:"likeCount"`
	CommentCount int64              `json:"commentCount"`
	UserID       int64              `json:"userId"`
	ToyID        int64              `json:"toyId"`
	CreatedAt    time.Time          `json:"createdAt"`
	User         snapshotReviewUser `json:"user"`
	Images       []string           `json:"images"`
	AssetPaths   []string           `json:"asset_paths"`
	Replies      []snapshotReply    `json:"replies"`
}

type snapshot struct {
	FetchedAt time.Time                   `json:"fetched_at"`
	Views     map[string]snapshotView     `json:"views"`
	Reviews   map[string][]snapshotReview `json:"reviews"`
	Users     map[string]snapshotSourceUser `json:"users"`
}

type importer struct {
	db        *sql.DB
	store     storage.ObjectStorage
	assetsDir string
	mediaIDs  map[string]string
	users     map[int64]string
	avatars   map[int64]string
}

func main() {
	snapshotPath := flag.String("snapshot", "server/seeds/beiyoujiang_snapshot.json", "快照 JSON 路径")
	assetsRoot := flag.String("assets-root", ".", "快照内 asset_path 的根目录")
	flag.Parse()

	dbURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if dbURL == "" {
		log.Fatal("缺少 DATABASE_URL")
	}
	db, err := database.Open(dbURL)
	if err != nil {
		log.Fatalf("打开数据库失败：%v", err)
	}
	if db == nil {
		log.Fatal("DATABASE_URL 未启用数据库存储")
	}
	defer db.Close()

	imp := &importer{
		db:        db,
		store:     storage.NewObjectStorageFromEnv(),
		assetsDir: *assetsRoot,
		mediaIDs:  map[string]string{},
		users:     map[int64]string{},
		avatars:   map[int64]string{},
	}
	if _, unavailable := imp.store.(storage.UnavailableMediaStorage); unavailable {
		log.Fatal("缺少媒体存储配置（MEDIA_STORAGE_DIR 或对象存储环境变量）")
	}

	raw, err := os.ReadFile(*snapshotPath)
	if err != nil {
		log.Fatalf("读取快照失败：%v", err)
	}
	// 同步脚本以 UTF-8 BOM 写出，去掉 BOM 便于解析。
	raw = []byte(strings.TrimPrefix(strings.TrimPrefix(string(raw), "\ufeff"), "\xff\xfe"))
	var snap snapshot
	if err := json.Unmarshal(raw, &snap); err != nil {
		log.Fatalf("解析快照失败：%v", err)
	}
	if len(snap.Views) == 0 {
		log.Fatal("快照缺少视图数据")
	}

	ctx := context.Background()
	if err := imp.ensureImporterUser(ctx); err != nil {
		log.Fatalf("初始化导入用户失败：%v", err)
	}

	toys, viewKeys, err := collectToys(&snap)
	if err != nil {
		log.Fatalf("整理快照数据失败：%v", err)
	}
	if err := imp.importToys(ctx, &snap, toys, viewKeys); err != nil {
		log.Fatalf("导入榜单失败：%v", err)
	}
	counts, err := imp.importReviews(ctx, &snap, toys)
	if err != nil {
		log.Fatalf("导入评价失败：%v", err)
	}

	log.Printf("导入完成：商品 %d，榜单视图 %d，评价 %d（回复 %d），评价配图 %d，用户 %d",
		len(toys), len(viewKeys), counts.reviews, counts.replies, counts.media, len(imp.users))
}

type toyEntry struct {
	sourceID string
	toy      snapshotToy
	rank     int
	views    []string
}

type importCounts struct {
	reviews int
	replies int
	media   int
}

// collectToys 去重商品并确定默认榜（综合热榜）名次；各视图的顺序在
// importToys 中按视图逐一写入 ranking_toy_rankings。
func collectToys(snap *snapshot) (map[string]*toyEntry, []string, error) {
	toys := map[string]*toyEntry{}
	overall := snap.Views["|"]
	for i := range overall.Items {
		t := overall.Items[i]
		rank := t.Rank
		if rank <= 0 {
			rank = i + 1
		}
		toys[strconv.Itoa(t.ID)] = &toyEntry{sourceID: strconv.Itoa(t.ID), toy: t, rank: rank}
	}
	if overall.WeeklyTop != nil {
		t := *overall.WeeklyTop
		rank := t.Rank
		if rank <= 0 {
			rank = 1
		}
		if existing, ok := toys[strconv.Itoa(t.ID)]; ok {
			if rank < existing.rank {
				existing.rank = rank
			}
		} else {
			toys[strconv.Itoa(t.ID)] = &toyEntry{sourceID: strconv.Itoa(t.ID), toy: t, rank: rank}
		}
	}
	// 只出现在分类/标签视图的商品排在综合榜之后，保持确定性顺序。
	fallback := 1000
	viewKeys := make([]string, 0, len(snap.Views))
	for key := range snap.Views {
		viewKeys = append(viewKeys, key)
	}
	sort.Strings(viewKeys)
	for _, key := range viewKeys {
		if key == "|" {
			continue
		}
		view := snap.Views[key]
		for i := range view.Items {
			id := strconv.Itoa(view.Items[i].ID)
			if _, ok := toys[id]; ok {
				continue
			}
			t := view.Items[i]
			toys[id] = &toyEntry{sourceID: id, toy: t, rank: fallback}
			fallback++
		}
		if view.WeeklyTop != nil {
			id := strconv.Itoa(view.WeeklyTop.ID)
			if _, ok := toys[id]; !ok {
				t := *view.WeeklyTop
				toys[id] = &toyEntry{sourceID: id, toy: t, rank: fallback}
				fallback++
			}
		}
	}
	return toys, viewKeys, nil
}

func (imp *importer) ensureImporterUser(ctx context.Context) error {
	if _, err := imp.db.ExecContext(ctx, `
		INSERT INTO users (id, username, status) VALUES ($1, $2, 'active')
		ON CONFLICT (id) DO NOTHING`, importerUserID, importerUsername); err != nil {
		return err
	}
	_, err := imp.db.ExecContext(ctx, `
		INSERT INTO user_profiles (user_id, nickname, level) VALUES ($1, $2, 1)
		ON CONFLICT (user_id) DO UPDATE SET nickname = EXCLUDED.nickname, updated_at = now()`,
		importerUserID, importerNickname)
	return err
}

func (imp *importer) importToys(ctx context.Context, snap *snapshot, toys map[string]*toyEntry, viewKeys []string) error {
	// 先把所有引用到的图片放进对象存储，再在事务里写库。
	coverMedia := map[string]string{}
	heroMedia := map[string]string{}
	for id, entry := range toys {
		if entry.toy.AssetPath != "" {
			mediaID, err := imp.importMedia(ctx, entry.toy.AssetPath, "detail")
			if err != nil {
				return fmt.Errorf("封面图导入失败（toy %s）：%w", id, err)
			}
			coverMedia[id] = mediaID
		}
		if entry.toy.HeroAssetPath != "" {
			mediaID, err := imp.importMedia(ctx, entry.toy.HeroAssetPath, "detail")
			if err != nil {
				return fmt.Errorf("主图导入失败（toy %s）：%w", id, err)
			}
			heroMedia[id] = mediaID
		}
	}

	tx, err := imp.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for id, entry := range toys {
		coverID := coverMedia[id]
		heroID := heroMedia[id]
		if err := imp.upsertToy(ctx, tx, entry, coverID, heroID); err != nil {
			return fmt.Errorf("商品 %s 写入失败：%w", id, err)
		}
	}

	// 视图名次：删除当前视图旧行后按快照顺序重插。
	viewTemp := `CREATE TEMP TABLE _byj_views (view_key text PRIMARY KEY, tab_key text NOT NULL, category_key text NOT NULL) ON COMMIT DROP`
	if _, err := tx.ExecContext(ctx, viewTemp); err != nil {
		return err
	}
	for _, key := range viewKeys {
		parts := strings.SplitN(key, "|", 2)
		tabKey, categoryKey := parts[0], parts[1]
		if _, err := tx.ExecContext(ctx, `INSERT INTO _byj_views (view_key, tab_key, category_key) VALUES ($1, $2, $3)`, key, tabKey, categoryKey); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM ranking_toy_rankings WHERE source_provider = $1 AND view_key = $2`, sourceProvider, key); err != nil {
			return err
		}
		view := snap.Views[key]
		position := 0
		insert := func(t snapshotToy, weeklyTop bool) error {
			position++
			rank := t.Rank
			if rank <= 0 {
				rank = position
			}
			_, err := tx.ExecContext(ctx, `
				INSERT INTO ranking_toy_rankings
					(source_provider, view_key, tab_key, category_key, toy_id, rank, is_weekly_top, snapshot_fetched_at)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
				ON CONFLICT (source_provider, view_key, toy_id) DO UPDATE
				SET rank = EXCLUDED.rank, is_weekly_top = EXCLUDED.is_weekly_top,
				    snapshot_fetched_at = EXCLUDED.snapshot_fetched_at, updated_at = now()`,
				sourceProvider, key, tabKey, categoryKey, "byj-"+strconv.Itoa(t.ID), position, weeklyTop, snap.FetchedAt)
			return err
		}
		if view.WeeklyTop != nil {
			if err := insert(*view.WeeklyTop, true); err != nil {
				return err
			}
		}
		for i := range view.Items {
			if err := insert(view.Items[i], false); err != nil {
				return err
			}
		}
	}

	// 既有商品若不再出现在任何视图中（含历史种子），停用而不是删除，
	// 保留其上的用户状态与评论。
	if _, err := tx.ExecContext(ctx, `
		UPDATE ranking_toys SET active = false, updated_at = now()
		WHERE active AND NOT EXISTS (
			SELECT 1 FROM ranking_toy_rankings r
			WHERE r.toy_id = ranking_toys.id AND r.source_provider = $1
		)`, sourceProvider); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM ranking_toy_rankings r
		USING ranking_toys t
		WHERE r.toy_id = t.id AND r.source_provider = $1 AND t.active = false`, sourceProvider); err != nil {
		return err
	}
	// 视图集合收缩时清掉遗留视图的旧名次。
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM ranking_toy_rankings r
		WHERE r.source_provider = $1 AND NOT EXISTS (
			SELECT 1 FROM _byj_views v WHERE v.view_key = r.view_key
		)`, sourceProvider); err != nil {
		return err
	}
	return tx.Commit()
}

func (imp *importer) upsertToy(ctx context.Context, tx *sql.Tx, entry *toyEntry, coverID, heroID string) error {
	t := entry.toy
	tags := []string{}
	for _, tag := range strings.Split(t.Tags, ",") {
		tag = strings.TrimSpace(tag)
		if tag != "" {
			tags = append(tags, tag)
		}
	}
	segments := []string{}
	if t.Stimulation != "" {
		segments = append(segments, t.Stimulation)
	}
	category := t.Category
	if category == "" {
		category = "CUP"
	}

	// 保留“源站基线 + 本站用户增量”：先读取上一次导入的基线，再平移。
	var (
		wantCount       int64
		ratingTotal     int64
		ratingCount     int64
		prevSourceWant  int64
		prevSourceTotal int64
		prevSourceCount int64
	)
	err := tx.QueryRowContext(ctx, `
		SELECT want_count, rating_total_centi, rating_count,
		       source_want_count, source_rating_total_centi, source_rating_count
		FROM ranking_toys WHERE id = $1`, "byj-"+entry.sourceID).Scan(
		&wantCount, &ratingTotal, &ratingCount,
		&prevSourceWant, &prevSourceTotal, &prevSourceCount)
	if errors.Is(err, sql.ErrNoRows) {
		wantCount = t.WantCount
		ratingCount = int64(t.ReviewCount)
		ratingTotal = int64(math.Round(t.Rating*100)) * ratingCount
	} else if err != nil {
		return err
	} else {
		wantCount = clampNonNegative(wantCount - prevSourceWant + t.WantCount)
		ratingCount = clampNonNegative(ratingCount - prevSourceCount + int64(t.ReviewCount))
		ratingTotal = clampNonNegative(ratingTotal - prevSourceTotal + int64(math.Round(t.Rating*100))*int64(t.ReviewCount))
	}

	assetKey := ""
	if t.AssetPath != "" {
		assetKey = filepath.Base(t.AssetPath)
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO ranking_toys (
			id, rank, name, merchant, release_year, description, tags, asset_key,
			want_count, rating_total_centi, rating_count, category, segments, active,
			source_provider, source_toy_id, source_updated_at,
			source_want_count, source_rating_total_centi, source_rating_count,
			cover_media_id, hero_media_id, coupon_url, source_url, updated_at
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8,
			$9, $10, $11, $12, $13, true,
			$14, $15, $16,
			$17, $18, $19,
			NULLIF($20, ''), NULLIF($21, ''), $22, $23, now()
		)
		ON CONFLICT (id) DO UPDATE SET
			rank = EXCLUDED.rank,
			name = EXCLUDED.name,
			merchant = EXCLUDED.merchant,
			release_year = EXCLUDED.release_year,
			description = EXCLUDED.description,
			tags = EXCLUDED.tags,
			asset_key = EXCLUDED.asset_key,
			want_count = EXCLUDED.want_count,
			rating_total_centi = EXCLUDED.rating_total_centi,
			rating_count = EXCLUDED.rating_count,
			category = EXCLUDED.category,
			segments = EXCLUDED.segments,
			active = true,
			source_provider = EXCLUDED.source_provider,
			source_toy_id = EXCLUDED.source_toy_id,
			source_updated_at = EXCLUDED.source_updated_at,
			source_want_count = EXCLUDED.source_want_count,
			source_rating_total_centi = EXCLUDED.source_rating_total_centi,
			source_rating_count = EXCLUDED.source_rating_count,
			cover_media_id = EXCLUDED.cover_media_id,
			hero_media_id = EXCLUDED.hero_media_id,
			coupon_url = EXCLUDED.coupon_url,
			source_url = EXCLUDED.source_url,
			updated_at = now()`,
		"byj-"+entry.sourceID, entry.rank, t.Name, t.Merchant, t.ReleaseYear, t.Description,
		tags, assetKey,
		wantCount, ratingTotal, ratingCount, category, segments,
		sourceProvider, entry.sourceID, nullableTime(t.UpdatedAt),
		t.WantCount, int64(math.Round(t.Rating*100))*int64(t.ReviewCount), t.ReviewCount,
		coverID, heroID, t.ShopLink, "https://beiyoujiang.com/bang/"+entry.sourceID)
	return err
}

func (imp *importer) importReviews(ctx context.Context, snap *snapshot, toys map[string]*toyEntry) (importCounts, error) {
	counts := importCounts{}
	// 评价配图先全部入对象存储。
	reviewMedia := map[string][]string{}
	for toyID, reviews := range snap.Reviews {
		if _, ok := toys[toyID]; !ok {
			continue
		}
		for _, review := range reviews {
			ids := make([]string, 0, len(review.AssetPaths))
			for _, path := range review.AssetPaths {
				mediaID, err := imp.importMedia(ctx, path, "detail")
				if err != nil {
					return counts, fmt.Errorf("评价配图导入失败（review %d）：%w", review.ID, err)
				}
				ids = append(ids, mediaID)
			}
			reviewMedia[fmt.Sprintf("%d:%d", review.ToyID, review.ID)] = ids
		}
	}
	// 评价用户头像同样先入对象存储，再随用户资料写入。
	userIDs := make([]string, 0, len(snap.Users))
	for id := range snap.Users {
		userIDs = append(userIDs, id)
	}
	sort.Slice(userIDs, func(i, j int) bool { return userIDs[i] < userIDs[j] })
	for _, id := range userIDs {
		user := snap.Users[id]
		if user.ID <= 0 {
			continue
		}
		if user.AvatarAssetPath != "" {
			mediaID, err := imp.importMedia(ctx, user.AvatarAssetPath, "thumb")
			if err != nil {
				return counts, fmt.Errorf("头像导入失败（user %d）：%w", user.ID, err)
			}
			imp.avatars[user.ID] = mediaID
		}
		if err := imp.ensureSourceUser(ctx, user.ID, user.Username, user.Level); err != nil {
			return counts, err
		}
	}

	for toyID, reviews := range snap.Reviews {
		if _, ok := toys[toyID]; !ok {
			continue
		}
		distribution := map[int]int64{}
		for _, review := range reviews {
			if err := imp.ensureSourceUser(ctx, review.UserID, review.User.Username, review.User.Level); err != nil {
				return counts, err
			}
			if err := imp.upsertReview(ctx, toyID, review); err != nil {
				return counts, fmt.Errorf("评价 %d 写入失败：%w", review.ID, err)
			}
			counts.reviews++
			if score := ratingScaleScore(review.Score); score > 0 {
				distribution[score]++
			}
			commentID := fmt.Sprintf("byj-review-%08d", review.ID)
			if err := imp.replaceCommentMedia(ctx, commentID, reviewMedia[fmt.Sprintf("%d:%d", review.ToyID, review.ID)]); err != nil {
				return counts, err
			}
			counts.media += len(review.AssetPaths)
			if rating := ratingScaleScore(review.Score); rating > 0 {
				if err := imp.setReviewerRating(ctx, toyID, review.UserID, rating); err != nil {
					return counts, err
				}
			}
			for _, reply := range review.Replies {
				if len(reply.ReplyToUser) > 0 && string(reply.ReplyToUser) != "null" {
					var replyTo snapshotReplyUser
					if err := json.Unmarshal(reply.ReplyToUser, &replyTo); err == nil && replyTo.ID > 0 {
						if err := imp.ensureSourceUser(ctx, replyTo.ID, replyTo.Username, replyTo.Level); err != nil {
							return counts, err
						}
					}
				}
				if err := imp.ensureSourceUser(ctx, reply.UserID, reply.Username, reply.Level); err != nil {
					return counts, err
				}
				if err := imp.upsertReply(ctx, toyID, commentID, review.CreatedAt, reply); err != nil {
					return counts, fmt.Errorf("回复 %d 写入失败：%w", reply.ID, err)
				}
				counts.replies++
			}
		}
		if err := imp.baselineRatingDistribution(ctx, toyID, distribution); err != nil {
			return counts, err
		}
	}
	return counts, nil
}

func (imp *importer) ensureSourceUser(ctx context.Context, sourceUserID int64, username string, level int) error {
	if sourceUserID <= 0 {
		return fmt.Errorf("评价用户缺少 userId")
	}
	if id, ok := imp.users[sourceUserID]; ok {
		return imp.upsertProfile(ctx, id, username, level)
	}
	ourID := fmt.Sprintf("byj-user-%d", sourceUserID)
	if _, err := imp.db.ExecContext(ctx, `
		INSERT INTO users (id, username, status) VALUES ($1, $2, 'active')
		ON CONFLICT (id) DO NOTHING`, ourID, fmt.Sprintf("byj_u%d", sourceUserID)); err != nil {
		return err
	}
	imp.users[sourceUserID] = ourID
	return imp.upsertProfile(ctx, ourID, username, level)
}

func (imp *importer) upsertProfile(ctx context.Context, userID, nickname string, level int) error {
	if strings.TrimSpace(nickname) == "" {
		nickname = userID
	}
	if level < 1 {
		level = 1
	}
	var avatar any
	if mediaID, ok := imp.avatars[avatarSourceUserID(userID)]; ok && mediaID != "" {
		avatar = mediaID
	}
	_, err := imp.db.ExecContext(ctx, `
		INSERT INTO user_profiles (user_id, nickname, level, avatar_media_id) VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id) DO UPDATE SET
			nickname = EXCLUDED.nickname,
			level = EXCLUDED.level,
			avatar_media_id = COALESCE(EXCLUDED.avatar_media_id, user_profiles.avatar_media_id),
			updated_at = now()`,
		userID, nickname, level, avatar)
	return err
}

// avatarSourceUserID 从合成用户 ID（byj-user-<n>）还原源站用户数字 ID。
func avatarSourceUserID(ourID string) int64 {
	value := strings.TrimPrefix(ourID, "byj-user-")
	id, _ := strconv.ParseInt(value, 10, 64)
	return id
}

func (imp *importer) upsertReview(ctx context.Context, toyID string, review snapshotReview) error {
	commentID := fmt.Sprintf("byj-review-%08d", review.ID)
	sourceCommentID := fmt.Sprintf("r%d", review.ID)
	_, err := imp.db.ExecContext(ctx, `
		INSERT INTO ranking_toy_comments (
			id, toy_id, author_id, content, like_count, created_at, updated_at,
			root_id, reply_count, source_provider, source_comment_id
		) VALUES (
			$1, $2, $3, $4, $5, $6, $6,
			$1, $7, $8, $9
		)
		ON CONFLICT (source_provider, toy_id, source_comment_id)
		WHERE source_provider <> '' AND source_comment_id IS NOT NULL
		DO UPDATE SET content = EXCLUDED.content, like_count = EXCLUDED.like_count, updated_at = now()`,
		commentID, "byj-"+toyID, fmt.Sprintf("byj-user-%d", review.UserID),
		htmlToText(review.Content), review.LikeCount, review.CreatedAt,
		review.CommentCount, sourceProvider, sourceCommentID)
	return err
}

func (imp *importer) upsertReply(ctx context.Context, toyID, rootID string, rootCreated time.Time, reply snapshotReply) error {
	commentID := fmt.Sprintf("byj-reply-%08d", reply.ID)
	sourceCommentID := fmt.Sprintf("p%d", reply.ID)
	replyToUserID, err := imp.parseReplyToUser(ctx, reply.ReplyToUser)
	if err != nil {
		return err
	}
	var replyToUserArg any
	if replyToUserID != "" {
		replyToUserArg = replyToUserID
	}
	_, err = imp.db.ExecContext(ctx, `
		INSERT INTO ranking_toy_comments (
			id, toy_id, author_id, content, created_at, updated_at,
			root_id, parent_id, reply_to_user_id, source_provider, source_comment_id
		) VALUES (
			$1, $2, $3, $4, $5, $5,
			$6, $6, $7, $8, $9
		)
		ON CONFLICT (source_provider, toy_id, source_comment_id)
		WHERE source_provider <> '' AND source_comment_id IS NOT NULL
		DO UPDATE SET content = EXCLUDED.content, updated_at = now()`,
		commentID, "byj-"+toyID, fmt.Sprintf("byj-user-%d", reply.UserID),
		htmlToText(reply.Content), rootCreated, rootID, replyToUserArg,
		sourceProvider, sourceCommentID)
	return err
}

func (imp *importer) setReviewerRating(ctx context.Context, toyID string, sourceUserID int64, rating int) error {
	_, err := imp.db.ExecContext(ctx, `
		INSERT INTO ranking_toy_user_states (toy_id, user_id, rating)
		VALUES ($1, $2, $3)
		ON CONFLICT (toy_id, user_id) DO UPDATE SET rating = EXCLUDED.rating, updated_at = now()`,
		"byj-"+toyID, fmt.Sprintf("byj-user-%d", sourceUserID), rating)
	return err
}

func (imp *importer) replaceCommentMedia(ctx context.Context, commentID string, mediaIDs []string) error {
	if _, err := imp.db.ExecContext(ctx, `DELETE FROM ranking_toy_comment_media WHERE comment_id = $1`, commentID); err != nil {
		return err
	}
	for order, mediaID := range mediaIDs {
		if _, err := imp.db.ExecContext(ctx, `
			INSERT INTO ranking_toy_comment_media (comment_id, media_id, sort_order)
			VALUES ($1, $2, $3) ON CONFLICT (comment_id, media_id) DO NOTHING`,
			commentID, mediaID, order); err != nil {
			return err
		}
	}
	return nil
}

// baselineRatingDistribution 写入源站评价的分布基线；本站用户的增量
// （source_rating_count 之外的部分）在重导入时保留。
func (imp *importer) baselineRatingDistribution(ctx context.Context, toyID string, distribution map[int]int64) error {
	// 先把旧基线清零，只留本站增量，再叠加新基线。
	if _, err := imp.db.ExecContext(ctx, `
		UPDATE ranking_toy_rating_distribution
		SET rating_count = GREATEST(rating_count - source_rating_count, 0), source_rating_count = 0
		WHERE toy_id = $1 AND source_rating_count > 0`, "byj-"+toyID); err != nil {
		return err
	}
	for score := 1; score <= 10; score++ {
		count := distribution[score]
		if count == 0 {
			continue
		}
		if _, err := imp.db.ExecContext(ctx, `
			INSERT INTO ranking_toy_rating_distribution (toy_id, score, rating_count, source_rating_count)
			VALUES ($1, $2, $3, $3)
			ON CONFLICT (toy_id, score) DO UPDATE SET
				rating_count = ranking_toy_rating_distribution.rating_count + EXCLUDED.rating_count,
				source_rating_count = EXCLUDED.source_rating_count`,
			"byj-"+toyID, score, count); err != nil {
			return err
		}
	}
	return nil
}

// importMedia 把快照引用的本地缓存图片导入对象存储并登记媒体资产。
// 可解码图片统一生成 original/detail/thumb 三个 JPEG 变体（与 worker 的
// media_variants 写入约定一致），并把 media_assets.object_key 指向展示用
// 变体对象（displayVariant 为 "thumb" 或 "detail"），客户端不必下载多兆
// 原图；源对象仍保留并登记为 source 变体。无法解码的文件按旧行为只登记
// 源对象。
func (imp *importer) importMedia(ctx context.Context, relPath, displayVariant string) (string, error) {
	relPath = strings.TrimSpace(relPath)
	if relPath == "" {
		return "", nil
	}
	if mediaID, ok := imp.mediaIDs[relPath]; ok {
		return mediaID, nil
	}
	filePath := filepath.Join(imp.assetsDir, filepath.FromSlash(relPath))
	data, err := os.ReadFile(filePath)
	if err != nil {
		return "", err
	}
	baseName := filepath.Base(relPath)
	rawKey := defaultObjectPrefix + baseName
	rawMime := mime.TypeByExtension(strings.ToLower(filepath.Ext(rawKey)))
	if rawMime == "" {
		rawMime = "application/octet-stream"
	}
	sum := sha256.Sum256(data)
	rawSHA := hex.EncodeToString(sum[:])
	rawW, rawH := 0, 0
	if config, _, configErr := image.DecodeConfig(bytes.NewReader(data)); configErr == nil {
		rawW, rawH = config.Width, config.Height
	}

	var proc *media.ProcessResult
	if strings.HasPrefix(rawMime, "image/") {
		if processed, procErr := media.ProcessImage(bytes.NewReader(data)); procErr != nil {
			log.Printf("图片处理失败 %s：%v", relPath, procErr)
		} else {
			proc = processed
		}
	}
	displayKey, displayMime := rawKey, rawMime
	displayW, displayH, displaySize := rawW, rawH, int64(len(data))
	displaySHA := rawSHA
	if proc != nil {
		variant := proc.Detail
		if displayVariant == "thumb" {
			variant = proc.Thumb
		}
		displayKey = variantObjectKey(rawKey, variant.Variant)
		displayMime = variant.MimeType
		displayW, displayH = variant.Width, variant.Height
		displaySize = variant.SizeBytes
		displaySHA = variant.SHA256
	}

	var mediaID, currentKey string
	err = imp.db.QueryRowContext(ctx, `
		SELECT id, object_key FROM media_assets
		WHERE owner_id = $1 AND original_name = $2 AND deleted_at IS NULL`,
		importerUserID, baseName).Scan(&mediaID, &currentKey)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		mediaID = "mda-" + randomHex(12)
		currentKey = ""
		if err := imp.store.Put(ctx, rawKey, rawMime, bytes.NewReader(data), int64(len(data))); err != nil {
			return "", fmt.Errorf("对象存储写入失败 %s：%w", rawKey, err)
		}
		if _, err := imp.db.ExecContext(ctx, `
			INSERT INTO media_assets (id, owner_id, object_key, original_name, mime_type, width, height, size, sha256, status, completed_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'ready', now())`,
			mediaID, importerUserID, displayKey, baseName, displayMime,
			displayW, displayH, displaySize, displaySHA); err != nil {
			return "", err
		}
	case err != nil:
		return "", err
	case currentKey != displayKey:
		// 旧版导入只登记原图；重跑导入时把展示键与描述信息升级为变体。
		if _, err := imp.db.ExecContext(ctx, `
			UPDATE media_assets SET object_key = $2, mime_type = $3, width = $4, height = $5,
			       size = $6, sha256 = $7, updated_at = now()
			WHERE id = $1`,
			mediaID, displayKey, displayMime, displayW, displayH, displaySize, displaySHA); err != nil {
			return "", err
		}
	}

	if err := imp.ensureMediaVariants(ctx, mediaID, rawKey, rawMime, rawW, rawH, int64(len(data)), rawSHA, proc); err != nil {
		return "", err
	}
	imp.mediaIDs[relPath] = mediaID
	return mediaID, nil
}

func variantObjectKey(rawKey, variant string) string {
	return strings.TrimSuffix(rawKey, filepath.Ext(rawKey)) + "_" + variant + ".jpg"
}

// ensureMediaVariants 幂等补齐 media_variants：四个核心变体已就绪则跳过
// （避免重跑导入反复上传对象），否则上传变体对象并逐行 UPSERT。
func (imp *importer) ensureMediaVariants(ctx context.Context, mediaID, rawKey, rawMime string, rawW, rawH int, rawSize int64, rawSHA string, proc *media.ProcessResult) error {
	var readyCount int
	if err := imp.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM media_variants
		WHERE media_id = $1 AND status = 'ready'
		  AND variant IN ('source', 'original', 'detail', 'thumb')`, mediaID).Scan(&readyCount); err != nil {
		return err
	}
	variants := []media.ProcessedVariant{{
		Variant: "source", MimeType: rawMime, Width: rawW, Height: rawH,
		SizeBytes: rawSize, SHA256: rawSHA,
	}}
	if proc != nil {
		variants = append(variants, proc.Original, proc.Detail, proc.Thumb)
	}
	if readyCount >= len(variants) {
		return nil
	}
	for _, variant := range variants {
		key := rawKey
		if variant.Variant != "source" {
			key = variantObjectKey(rawKey, variant.Variant)
			if err := imp.store.Put(ctx, key, variant.MimeType, bytes.NewReader(variant.Data), variant.SizeBytes); err != nil {
				return fmt.Errorf("对象存储写入失败 %s：%w", key, err)
			}
		}
		if _, err := imp.db.ExecContext(ctx, `
			INSERT INTO media_variants (media_id, variant, object_key, mime_type, width, height, size_bytes, sha256, status, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'ready', $9, $9)
			ON CONFLICT (media_id, variant) DO UPDATE SET
				object_key = EXCLUDED.object_key,
				mime_type = EXCLUDED.mime_type,
				width = EXCLUDED.width,
				height = EXCLUDED.height,
				size_bytes = EXCLUDED.size_bytes,
				sha256 = EXCLUDED.sha256,
				status = 'ready',
				updated_at = EXCLUDED.updated_at`,
			mediaID, variant.Variant, key, variant.MimeType, variant.Width, variant.Height,
			variant.SizeBytes, variant.SHA256, time.Now().UTC()); err != nil {
			return fmt.Errorf("登记媒体变体 %s/%s 失败：%w", mediaID, variant.Variant, err)
		}
	}
	return nil
}

var (
	tagDivEnd  = regexp.MustCompile(`(?i)</div\s*>`)
	tagDivOpen = regexp.MustCompile(`(?i)<div[^>]*>`)
	tagImage   = regexp.MustCompile(`(?i)<img[^>]*>`)
	tagAny     = regexp.MustCompile(`</?[a-zA-Z][^>]*>`)
)

// htmlToText 把源站评价的富文本清洗成纯文本：换行保留，表情图与样式
// 标签剔除（表情是源站站内装饰，不随数据导入）。
func htmlToText(raw string) string {
	text := raw
	text = strings.ReplaceAll(text, "<br>", "\n")
	text = strings.ReplaceAll(text, "<br/>", "\n")
	text = strings.ReplaceAll(text, "<br />", "\n")
	text = tagDivEnd.ReplaceAllString(text, "\n")
	text = tagDivOpen.ReplaceAllString(text, "")
	text = tagImage.ReplaceAllString(text, "")
	text = tagAny.ReplaceAllString(text, "")
	replacer := strings.NewReplacer(
		"&nbsp;", " ", "&amp;", "&", "&lt;", "<", "&gt;", ">", "&quot;", "\"", "&#39;", "'", "&apos;", "'",
	)
	text = replacer.Replace(text)
	lines := strings.Split(text, "\n")
	kept := make([]string, 0, len(lines))
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line != "" {
			kept = append(kept, line)
		}
	}
	return strings.Join(kept, "\n")
}

// ratingScaleScore 把源站 1-5 星（含半星）折算为本站 1-10 分。
func ratingScaleScore(score float64) int {
	if score <= 0 {
		return 0
	}
	rating := int(math.Round(score * 2))
	if rating < 1 {
		rating = 1
	}
	if rating > 10 {
		rating = 10
	}
	return rating
}

func clampNonNegative(value int64) int64 {
	if value < 0 {
		return 0
	}
	return value
}

func nullableTime(t time.Time) any {
	if t.IsZero() {
		return nil
	}
	return t
}

func randomHex(n int) string {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	return hex.EncodeToString(buf)
}
