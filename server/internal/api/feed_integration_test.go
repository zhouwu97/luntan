package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/auth"
	"github.com/zhouwu97/luntan/server/internal/platform/database"
)

// feedIntegrationServer 打开 DATABASE_URL 指向的真实 Postgres，应用全部迁移，
// 返回可直接调用 handler 的 Server。未配置 DATABASE_URL 时跳过，保证本地
// `go test ./...` 不需要数据库。
func feedIntegrationServer(t *testing.T) *Server {
	t.Helper()
	// 集成测试显式开启本地验证码回显；生产代码默认关闭该开关。
	t.Setenv("APP_ENV", "development")
	t.Setenv("ALLOW_DEV_AUTH_CODE", "true")
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Skip("DATABASE_URL 未配置，跳过真实 PostgreSQL Feed 集成测试")
	}
	db, err := database.Open(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	if err := database.Migrate(context.Background(), db, filepath.Join("..", "..", "migrations")); err != nil {
		t.Fatal(err)
	}
	return &Server{db: db}
}

func insertFeedFixtures(t *testing.T, s *Server) (communityID string, postIDs map[string]string) {
	t.Helper()
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	userID := "itest-user-" + suffix
	userName := "itest_" + suffix
	categoryID := "itest-cat-" + suffix
	communityID = "itest-com-" + suffix
	if _, err := s.db.Exec(`INSERT INTO users (id, username, status, created_at, updated_at) VALUES ($1, $2, 'active', now() - interval '7 days', now() - interval '7 days')`, userID, userName); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO user_profiles (user_id, nickname) VALUES ($1, $2)`, userID, "itest"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, $2, $3)`, categoryID, "itest", "itest-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, $4, 'active')`, communityID, categoryID, "itest-com-"+suffix, "itest"); err != nil {
		t.Fatal(err)
	}
	type postSpec struct {
		key      string
		ageHours int
		like     int64
		comment  int64
		bookmark int64
		share    int64
		view     int64
	}
	specs := []postSpec{
		{"p1", 72, 0, 0, 0, 0, 0},
		{"p2", 1, 5, 4, 3, 2, 100},
		{"p3", 24, 100, 80, 60, 40, 1000},
	}
	postIDs = make(map[string]string, len(specs))
	now := time.Now().UTC()
	for _, spec := range specs {
		id := "itest-post-" + suffix + "-" + spec.key
		publishedAt := now.Add(-time.Duration(spec.ageHours) * time.Hour)
		if _, err := s.db.Exec(`
			INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status,
				title, content, comment_count, like_count, bookmark_count, share_count, view_count,
				created_at, updated_at, published_at)
			VALUES ($1, $2, $3, 'normal', 'published', 'normal', $4, $5, $6, $7, $8, $9, $10, $11, $11, $11)`,
			id, userID, communityID, "itest", "body", spec.comment, spec.like, spec.bookmark, spec.share, spec.view, publishedAt); err != nil {
			t.Fatal(err)
		}
		postIDs[spec.key] = id
	}
	return communityID, postIDs
}

func fetchFeedIDs(t *testing.T, s *Server, sort, communityID string) []string {
	t.Helper()
	var all []string
	cursor := ""
	for page := 0; page < 10; page++ {
		u := fmt.Sprintf("/api/v1/feed/latest?sort=%s&community_id=%s&limit=2", sort, communityID)
		if cursor != "" {
			u += "&cursor=" + url.QueryEscape(cursor)
		}
		req := httptest.NewRequest(http.MethodGet, u, nil)
		rec := httptest.NewRecorder()
		s.latestFeed(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("sort=%s page=%d status=%d body=%s", sort, page, rec.Code, rec.Body.String())
		}
		var payload struct {
			Items []struct {
				ID string `json:"id"`
			} `json:"items"`
			Next *string `json:"next_cursor"`
			More bool    `json:"has_more"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
			t.Fatal(err)
		}
		for _, item := range payload.Items {
			all = append(all, item.ID)
		}
		if payload.Next == nil || !payload.More {
			break
		}
		cursor = *payload.Next
	}
	return all
}

func requireFeedOrder(t *testing.T, got []string, want []string, sort string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("sort=%s got %d ids, want %d: %v", sort, len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("sort=%s order=%v, want %v", sort, got, want)
		}
	}
}

func fetchFeedIDsWithLatestBy(t *testing.T, s *Server, sort, latestBy, communityID string) []string {
	t.Helper()
	var all []string
	cursor := ""
	for page := 0; page < 10; page++ {
		u := fmt.Sprintf("/api/v1/feed/latest?sort=%s&latest_by=%s&community_id=%s&limit=2", sort, latestBy, communityID)
		if cursor != "" {
			u += "&cursor=" + url.QueryEscape(cursor)
		}
		req := httptest.NewRequest(http.MethodGet, u, nil)
		rec := httptest.NewRecorder()
		s.latestFeed(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("sort=%s latest_by=%s page=%d status=%d body=%s", sort, latestBy, page, rec.Code, rec.Body.String())
		}
		var payload struct {
			Items []struct {
				ID string `json:"id"`
			} `json:"items"`
			Next *string `json:"next_cursor"`
			More bool    `json:"has_more"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
			t.Fatal(err)
		}
		for _, item := range payload.Items {
			all = append(all, item.ID)
		}
		if payload.Next == nil || !payload.More {
			break
		}
		cursor = *payload.Next
	}
	return all
}

// 固定三篇帖：p1 很旧零互动、p2 很新低互动、p3 一天前高互动。
// 期望排序：latest=[p2,p3,p1]（纯时间）、featured=[p3,p2,p1]（无时间衰减）、
// hot=[p2,p3,p1]（近期爆发领先）。
func TestFeedSortsAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	communityID, ids := insertFeedFixtures(t, s)

	// 为 p3 插入一条管理员推荐
	if _, err := s.db.Exec(`
		INSERT INTO home_recommendations (post_id, recommended_by, position, recommended_at)
		VALUES ($1, (SELECT author_id FROM posts WHERE id = $1), 1, now())`, ids["p3"]); err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		sort string
		want []string
	}{
		{"latest", []string{ids["p2"], ids["p3"], ids["p1"]}},
		{"featured", []string{ids["p3"], ids["p2"], ids["p1"]}},
		{"recommended", []string{ids["p3"]}},
		{"hot", []string{ids["p2"], ids["p3"], ids["p1"]}},
	}
	for _, tc := range cases {
		got := fetchFeedIDs(t, s, tc.sort, communityID)
		requireFeedOrder(t, got, tc.want, tc.sort)
	}
}

// 验收测试：拿三篇帖子测试按回复与按发帖排序
// A：09:00 发布，10:05 有回复
// B：10:00 发布，无回复
// C：09:30 发布，10:02 有回复
// 最新 → 按回复：A (10:05) -> C (10:02) -> B (10:00 发布)
// 最新 → 按发帖：B (10:00) -> C (09:30) -> A (09:00)
// 然后 10:10 给 C 发新评论 -> 刷新最新按回复：C (10:10) -> A (10:05) -> B (10:00)
func TestFeedLatestByCommentAndPostOrder(t *testing.T) {
	s := feedIntegrationServer(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	userID := "itest-abc-user-" + suffix
	categoryID := "itest-abc-cat-" + suffix
	communityID := "itest-abc-com-" + suffix
	if _, err := s.db.Exec(`INSERT INTO users (id, username, status, created_at, updated_at) VALUES ($1, $2, 'active', now() - interval '7 days', now() - interval '7 days')`, userID, "user_"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO community_categories (id, name, slug) VALUES ($1, $2, $3)`, categoryID, "abc", "abc-"+suffix); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO communities (id, category_id, slug, name, status) VALUES ($1, $2, $3, $4, 'active')`, communityID, categoryID, "abc-com-"+suffix, "abc"); err != nil {
		t.Fatal(err)
	}

	base := time.Date(2026, 8, 26, 9, 0, 0, 0, time.UTC)
	postA := "itest-post-A-" + suffix // 09:00
	postB := "itest-post-B-" + suffix // 10:00
	postC := "itest-post-C-" + suffix // 09:30

	createPost := func(id, title string, pubAt time.Time) {
		t.Helper()
		if _, err := s.db.Exec(`
			INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status,
				title, content, comment_count, like_count, bookmark_count, share_count, view_count,
				created_at, updated_at, published_at)
			VALUES ($1, $2, $3, 'normal', 'published', 'normal', $4, 'body', 0, 0, 0, 0, 0, $5, $5, $5)`,
			id, userID, communityID, title, pubAt); err != nil {
			t.Fatal(err)
		}
	}

	createPost(postA, "Post A", base)
	createPost(postB, "Post B", base.Add(60*time.Minute))
	createPost(postC, "Post C", base.Add(30*time.Minute))

	// A 10:05 (base + 65m) 回复
	if _, err := s.db.Exec(`
		INSERT INTO comments (id, post_id, author_id, root_id, content, publication_status, moderation_status, created_at, updated_at, published_at)
		VALUES ($1, $2, $3, $1, 'comment A', 'published', 'normal', $4, $4, $4)`,
		"cmt-A-"+suffix, postA, userID, base.Add(65*time.Minute)); err != nil {
		t.Fatal(err)
	}

	// C 10:02 (base + 62m) 回复
	if _, err := s.db.Exec(`
		INSERT INTO comments (id, post_id, author_id, root_id, content, publication_status, moderation_status, created_at, updated_at, published_at)
		VALUES ($1, $2, $3, $1, 'comment C1', 'published', 'normal', $4, $4, $4)`,
		"cmt-C1-"+suffix, postC, userID, base.Add(62*time.Minute)); err != nil {
		t.Fatal(err)
	}

	// 最新 -> 按回复: [A, C, B]
	orderComment := fetchFeedIDsWithLatestBy(t, s, "latest", "comment", communityID)
	requireFeedOrder(t, orderComment, []string{postA, postC, postB}, "latest_by=comment")

	// 最新 -> 按发帖: [B, C, A]
	orderPost := fetchFeedIDsWithLatestBy(t, s, "latest", "post", communityID)
	requireFeedOrder(t, orderPost, []string{postB, postC, postA}, "latest_by=post")

	// 10:10 给 C 发新评论 (base + 70m)
	if _, err := s.db.Exec(`
		INSERT INTO comments (id, post_id, author_id, root_id, content, publication_status, moderation_status, created_at, updated_at, published_at)
		VALUES ($1, $2, $3, $1, 'comment C2', 'published', 'normal', $4, $4, $4)`,
		"cmt-C2-"+suffix, postC, userID, base.Add(70*time.Minute)); err != nil {
		t.Fatal(err)
	}

	// 刷新按回复: [C, A, B]
	orderCommentUpdated := fetchFeedIDsWithLatestBy(t, s, "latest", "comment", communityID)
	requireFeedOrder(t, orderCommentUpdated, []string{postC, postA, postB}, "latest_by=comment after new reply")
}

// 评论排序分页使用首屏快照：翻页期间给旧页中的帖子新增回复，也不能把它从本次滚动中漏掉。
func TestFeedLatestByCommentKeepsSnapshotAcrossNewReply(t *testing.T) {
	s := feedIntegrationServer(t)
	communityID, ids := insertFeedFixtures(t, s)
	var authorID string
	if err := s.db.QueryRow(`SELECT author_id FROM posts WHERE id = $1`, ids["p1"]).Scan(&authorID); err != nil {
		t.Fatal(err)
	}

	now := time.Now().UTC()
	// 评论 ID 加运行时后缀：集成测试可能指向复用的数据库，固定 ID 会重复插入。
	snap := fmt.Sprintf("%d", time.Now().UnixNano())
	insertComment := func(id, postID string, createdAt time.Time) {
		t.Helper()
		if _, err := s.db.Exec(`
			INSERT INTO comments (id, post_id, author_id, root_id, content,
				publication_status, moderation_status, created_at, updated_at, published_at)
			VALUES ($1, $2, $3, $1, 'snapshot comment', 'published', 'normal', $4, $4, $4)`,
			id+"-"+snap, postID, authorID, createdAt); err != nil {
			t.Fatal(err)
		}
	}
	insertComment("snapshot-p1-old", ids["p1"], now.Add(-20*time.Minute))
	insertComment("snapshot-p2-old", ids["p2"], now.Add(-10*time.Minute))
	insertComment("snapshot-p3-old", ids["p3"], now.Add(-30*time.Minute))

	firstReq := httptest.NewRequest(http.MethodGet, "/api/v1/feed/latest?sort=latest&latest_by=comment&community_id="+url.QueryEscape(communityID)+"&limit=1", nil)
	firstRes := httptest.NewRecorder()
	s.latestFeed(firstRes, firstReq)
	if firstRes.Code != http.StatusOK {
		t.Fatalf("first page status=%d body=%s", firstRes.Code, firstRes.Body.String())
	}
	var first struct {
		Items []struct {
			ID string `json:"id"`
		} `json:"items"`
		Next *string `json:"next_cursor"`
	}
	if err := json.Unmarshal(firstRes.Body.Bytes(), &first); err != nil {
		t.Fatal(err)
	}
	if len(first.Items) != 1 || first.Items[0].ID != ids["p2"] || first.Next == nil {
		t.Fatalf("unexpected first page: %s", firstRes.Body.String())
	}

	// 这条回复发生在首屏快照之后；没有 as_of 时，p1 会被挪到游标之前而漏掉。
	insertComment("snapshot-p1-new", ids["p1"], now.Add(time.Hour))

	secondReq := httptest.NewRequest(http.MethodGet, "/api/v1/feed/latest?sort=latest&latest_by=comment&community_id="+url.QueryEscape(communityID)+"&limit=2&cursor="+url.QueryEscape(*first.Next), nil)
	secondRes := httptest.NewRecorder()
	s.latestFeed(secondRes, secondReq)
	if secondRes.Code != http.StatusOK {
		t.Fatalf("second page status=%d body=%s", secondRes.Code, secondRes.Body.String())
	}
	var second struct {
		Items []struct {
			ID string `json:"id"`
		} `json:"items"`
	}
	if err := json.Unmarshal(secondRes.Body.Bytes(), &second); err != nil {
		t.Fatal(err)
	}
	if len(second.Items) != 2 || second.Items[0].ID != ids["p1"] || second.Items[1].ID != ids["p3"] {
		t.Fatalf("snapshot page lost an item: %s", secondRes.Body.String())
	}
}

// 楼中楼：入口评论下按创建时间分页拉取整条回复线程（含孙级回复）。
func TestCommentThreadAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	_, postIDs := insertFeedFixtures(t, s)
	postID := postIDs["p1"]
	var authorID string
	if err := s.db.QueryRow(`SELECT author_id FROM posts WHERE id = $1`, postID).Scan(&authorID); err != nil {
		t.Fatal(err)
	}
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	rootID := "itest-ct-root-" + suffix
	now := time.Now().UTC()
	if _, err := s.db.Exec(`
		INSERT INTO comments (id, post_id, author_id, root_id, parent_id, content,
			publication_status, moderation_status, created_at, updated_at, published_at)
		VALUES ($1, $2, $3, $1, NULL, 'root', 'published', 'normal', $4, $4, $4)`,
		rootID, postID, authorID, now); err != nil {
		t.Fatal(err)
	}
	replyIDs := []string{"r1", "r2", "r3", "r4"}
	inserted := make([]string, 0, len(replyIDs))
	for i, key := range replyIDs {
		id := "itest-ct-" + key + "-" + suffix
		createdAt := now.Add(time.Duration(i) * time.Minute)
		parent := rootID
		if key == "r4" {
			parent = "itest-ct-r1-" + suffix // 孙级回复挂在 r1 下
		}
		if _, err := s.db.Exec(`
			INSERT INTO comments (id, post_id, author_id, root_id, parent_id, content,
				publication_status, moderation_status, created_at, updated_at, published_at)
			VALUES ($1, $2, $3, $4, $5, $6, 'published', 'normal', $7, $7, $7)`,
			id, postID, authorID, rootID, parent, key, createdAt); err != nil {
			t.Fatal(err)
		}
		inserted = append(inserted, id)
	}

	fetchReplies := func() []string {
		var all []string
		cursor := ""
		for page := 0; page < 10; page++ {
			u := fmt.Sprintf("/api/v1/comments/%s/replies?limit=2", rootID)
			if cursor != "" {
				u += "&cursor=" + url.QueryEscape(cursor)
			}
			req := httptest.NewRequest(http.MethodGet, u, nil)
			rec := httptest.NewRecorder()
			s.listCommentReplies(rec, req, rootID)
			if rec.Code != http.StatusOK {
				t.Fatalf("page=%d status=%d body=%s", page, rec.Code, rec.Body.String())
			}
			var payload struct {
				Items []struct {
					ID string `json:"id"`
				} `json:"items"`
				Next *string `json:"next_cursor"`
				More bool    `json:"has_more"`
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
				t.Fatal(err)
			}
			for _, item := range payload.Items {
				all = append(all, item.ID)
			}
			if payload.Next == nil || !payload.More {
				break
			}
			cursor = *payload.Next
		}
		return all
	}

	got := fetchReplies()
	if len(got) != len(inserted) {
		t.Fatalf("thread replies got %d ids, want %d: %v", len(got), len(inserted), got)
	}
	for i := range inserted {
		if got[i] != inserted[i] {
			t.Fatalf("thread reply order=%v, want %v", got, inserted)
		}
	}
}

// 屏蔽用户后，其帖子不再出现在该用户的 Feed 中；未登录公开查看不受影响。
func TestFeedExcludesBlockedAuthorAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	communityID, _ := insertFeedFixtures(t, s)

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	blockedUser := "itest-blocked-" + suffix
	blockedUsername := "blocked_" + suffix
	viewerUser := "itest-viewer-" + suffix
	blockedPost := "itest-blocked-post-" + suffix
	insertUser := func(id, username string) {
		t.Helper()
		if _, err := s.db.Exec(`INSERT INTO users (id, username, status, created_at, updated_at) VALUES ($1, $2, 'active', now() - interval '7 days', now() - interval '7 days')`, id, username); err != nil {
			t.Fatal(err)
		}
		if _, err := s.db.Exec(`INSERT INTO user_profiles (user_id, nickname) VALUES ($1, $2)`, id, "itest"); err != nil {
			t.Fatal(err)
		}
	}
	insertUser(blockedUser, blockedUsername)
	insertUser(viewerUser, "viewer_"+suffix)
	if _, err := s.db.Exec(`INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2)`, viewerUser, blockedUser); err != nil {
		t.Fatal(err)
	}
	publishedAt := time.Now().UTC().Add(-2 * time.Hour)
	if _, err := s.db.Exec(`
		INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status,
			title, content, comment_count, like_count, bookmark_count, share_count, view_count,
			created_at, updated_at, published_at)
		VALUES ($1, $2, $3, 'normal', 'published', 'normal', 'blocked', 'body', 0, 0, 0, 0, 0, $4, $4, $4)`,
		blockedPost, blockedUser, communityID, publishedAt); err != nil {
		t.Fatal(err)
	}

	original := resolveOptionalViewer
	t.Cleanup(func() { resolveOptionalViewer = original })

	resolveOptionalViewer = func(_ *Server, _ *http.Request) (auth.User, bool) {
		return auth.User{}, false
	}
	public := fetchFeedIDs(t, s, "latest", communityID)
	if !slices.Contains(public, blockedPost) {
		t.Fatalf("public feed should include blocked-author post, got %v", public)
	}

	resolveOptionalViewer = func(_ *Server, _ *http.Request) (auth.User, bool) {
		return auth.User{ID: viewerUser}, true
	}
	filtered := fetchFeedIDs(t, s, "latest", communityID)
	if slices.Contains(filtered, blockedPost) {
		t.Fatalf("feed should exclude blocked-author post, got %v", filtered)
	}
}

func TestCommentsExposeViewerLikeStateAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	_, postIDs := insertFeedFixtures(t, s)
	postID := postIDs["p1"]
	var authorID string
	if err := s.db.QueryRow(`SELECT author_id FROM posts WHERE id = $1`, postID).Scan(&authorID); err != nil {
		t.Fatal(err)
	}

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	viewer, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "comment_viewer_" + suffix,
		Password: "安全密码12345",
		Nickname: "评论查看者",
	}, auth.SessionMetadata{UserAgent: "comment-integration-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	commentID := "viewer-comment-" + suffix
	if _, err := s.db.Exec(`
		INSERT INTO comments (id, post_id, author_id, root_id, content, like_count,
			publication_status, moderation_status, created_at, updated_at, published_at)
		VALUES ($1, $2, $3, $1, 'viewer state', 1, 'published', 'normal', now(), now(), now())`,
		commentID, postID, authorID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.Exec(`INSERT INTO comment_reactions (comment_id, user_id, reaction_type) VALUES ($1, $2, 'like')`, commentID, viewer.User.ID); err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/posts/"+postID+"/comments", nil)
	req.Header.Set("Authorization", "Bearer "+viewer.AccessToken)
	res := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"viewer_state":{"has_liked":true,"has_disliked":false}`) {
		t.Fatalf("comments viewer state: status=%d body=%s", res.Code, res.Body.String())
	}
}

func TestCommentAttachmentsPostgresRoundTrip(t *testing.T) {
	s := feedIntegrationServer(t)
	_, postIDs := insertFeedFixtures(t, s)
	postID := postIDs["p1"]

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	userSession, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "attachment_user_" + suffix,
		Password: "安全密码12345",
		Nickname: "附件测试员",
	}, auth.SessionMetadata{UserAgent: "attachment-roundtrip-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	mediaID := "itest-media-" + suffix
	if _, err := s.db.Exec(`
		INSERT INTO media_assets (id, owner_id, status, mime_type, size, sha256, width, height, original_name, object_key, created_at, updated_at)
		VALUES ($1, $2, 'ready', 'image/png', 2048, $3, 1024, 768, 'test_image.png', $4, now(), now())`,
		mediaID, userSession.User.ID, "hash-"+suffix, "media/test/test_image_"+suffix+".png"); err != nil {
		t.Fatal(err)
	}

	// 1. 测试纯图片评论创建 -> 201 -> DB 校验
	reqImage := httptest.NewRequest(http.MethodPost, "/api/v1/posts/"+postID+"/comments", strings.NewReader(fmt.Sprintf(`{"content":"","media_ids":["%s"]}`, mediaID)))
	reqImage.Header.Set("Authorization", "Bearer "+userSession.AccessToken)
	reqImage.Header.Set("Idempotency-Key", "key-img-"+suffix)
	resImage := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(resImage, reqImage)
	if resImage.Code != http.StatusCreated {
		t.Fatalf("create image-only comment failed: status=%d body=%s", resImage.Code, resImage.Body.String())
	}
	var createdImageComment commentResponse
	if err := json.Unmarshal(resImage.Body.Bytes(), &createdImageComment); err != nil {
		t.Fatalf("unmarshal created comment failed: %v", err)
	}
	if createdImageComment.ID == "" {
		t.Fatal("expected non-empty created comment ID")
	}

	// 校验 comments 与 comment_media 数据库记录
	var dbContent string
	if err := s.db.QueryRow(`SELECT content FROM comments WHERE id = $1`, createdImageComment.ID).Scan(&dbContent); err != nil || dbContent != "" {
		t.Fatalf("expected empty db content, got err=%v content=%s", err, dbContent)
	}
	var dbMediaCount int
	if err := s.db.QueryRow(`SELECT count(*) FROM comment_media WHERE comment_id = $1 AND media_id = $2`, createdImageComment.ID, mediaID).Scan(&dbMediaCount); err != nil || dbMediaCount != 1 {
		t.Fatalf("expected 1 comment_media entry, got err=%v count=%d", err, dbMediaCount)
	}

	// 2. 测试纯贴纸评论创建 -> 201 -> DB 校验
	stickerID := "aad70d8d064f9eb79286c1393490716c"
	reqSticker := httptest.NewRequest(http.MethodPost, "/api/v1/posts/"+postID+"/comments", strings.NewReader(fmt.Sprintf(`{"content":"","sticker_id":"%s"}`, stickerID)))
	reqSticker.Header.Set("Authorization", "Bearer "+userSession.AccessToken)
	reqSticker.Header.Set("Idempotency-Key", "key-stk-"+suffix)
	resSticker := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(resSticker, reqSticker)
	if resSticker.Code != http.StatusCreated {
		t.Fatalf("create sticker-only comment failed: status=%d body=%s", resSticker.Code, resSticker.Body.String())
	}
	var createdStickerComment commentResponse
	if err := json.Unmarshal(resSticker.Body.Bytes(), &createdStickerComment); err != nil {
		t.Fatalf("unmarshal created sticker comment failed: %v", err)
	}
	var dbStickerID string
	if err := s.db.QueryRow(`SELECT sticker_id FROM comments WHERE id = $1`, createdStickerComment.ID).Scan(&dbStickerID); err != nil || dbStickerID != stickerID {
		t.Fatalf("expected db sticker_id=%s, got err=%v sticker_id=%s", stickerID, err, dbStickerID)
	}

	// 3. GET /posts/:id/comments 列表正向回查并断言媒体与贴纸数据结构
	reqGet := httptest.NewRequest(http.MethodGet, "/api/v1/posts/"+postID+"/comments?limit=20", nil)
	reqGet.Header.Set("Authorization", "Bearer "+userSession.AccessToken)
	resGet := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(resGet, reqGet)
	if resGet.Code != http.StatusOK {
		t.Fatalf("get comments failed: status=%d body=%s", resGet.Code, resGet.Body.String())
	}

	var listPayload struct {
		Items []commentResponse `json:"items"`
	}
	if err := json.Unmarshal(resGet.Body.Bytes(), &listPayload); err != nil {
		t.Fatalf("unmarshal comments list failed: %v", err)
	}

	var foundImageComment, foundStickerComment *commentResponse
	for i := range listPayload.Items {
		if listPayload.Items[i].ID == createdImageComment.ID {
			foundImageComment = &listPayload.Items[i]
		}
		if listPayload.Items[i].ID == createdStickerComment.ID {
			foundStickerComment = &listPayload.Items[i]
		}
	}

	if foundImageComment == nil {
		t.Fatalf("created image comment %s not found in list", createdImageComment.ID)
	}
	if len(foundImageComment.Media) != 1 || foundImageComment.Media[0].ID != mediaID {
		t.Fatalf("expected image comment media to contain %s, got %+v", mediaID, foundImageComment.Media)
	}
	if foundImageComment.Media[0].Type != "image" || foundImageComment.Media[0].Width != 1024 || foundImageComment.Media[0].Height != 768 {
		t.Fatalf("unexpected media metadata: %+v", foundImageComment.Media[0])
	}
	if len(foundImageComment.Attachments) != 1 || foundImageComment.Attachments[0].ID != mediaID {
		t.Fatalf("expected attachments to contain image attachment, got %+v", foundImageComment.Attachments)
	}

	if foundStickerComment == nil {
		t.Fatalf("created sticker comment %s not found in list", createdStickerComment.ID)
	}
	if foundStickerComment.StickerID == nil || *foundStickerComment.StickerID != stickerID {
		t.Fatalf("expected sticker comment sticker_id=%s, got %v", stickerID, foundStickerComment.StickerID)
	}
	if len(foundStickerComment.Attachments) != 1 || foundStickerComment.Attachments[0].Type != "sticker" || foundStickerComment.Attachments[0].StickerID != stickerID {
		t.Fatalf("expected attachments to contain sticker attachment, got %+v", foundStickerComment.Attachments)
	}
}

func TestUpdateCommentReturnsFullCommentResponse(t *testing.T) {
	s := feedIntegrationServer(t)
	_, postIDs := insertFeedFixtures(t, s)
	postID := postIDs["p1"]

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "comment_editor_" + suffix,
		Password: "安全密码12345",
		Nickname: "评论编辑者",
	}, auth.SessionMetadata{UserAgent: "comment-edit-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}

	mediaID := "edit-media-" + suffix
	if _, err := s.db.Exec(`
		INSERT INTO media_assets (id, owner_id, status, mime_type, size, sha256, width, height, original_name, object_key, created_at, updated_at)
		VALUES ($1, $2, 'ready', 'image/png', 2048, $3, 1024, 768, 'test_image.png', $4, now(), now())`,
		mediaID, session.User.ID, "hash-edit-"+suffix, "media/test/edit_image_"+suffix+".png"); err != nil {
		t.Fatal(err)
	}

	createReq := httptest.NewRequest(http.MethodPost, "/api/v1/posts/"+postID+"/comments", strings.NewReader(fmt.Sprintf(`{"content":"原始内容","media_ids":["%s"]}`, mediaID)))
	createReq.Header.Set("Authorization", "Bearer "+session.AccessToken)
	createReq.Header.Set("Idempotency-Key", "key-edit-"+suffix)
	createRes := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(createRes, createReq)
	if createRes.Code != http.StatusCreated {
		t.Fatalf("create comment failed: status=%d body=%s", createRes.Code, createRes.Body.String())
	}
	var created commentResponse
	if err := json.Unmarshal(createRes.Body.Bytes(), &created); err != nil {
		t.Fatalf("unmarshal created comment failed: %v", err)
	}

	likeReq := httptest.NewRequest(http.MethodPut, "/api/v1/comments/"+created.ID+"/like", nil)
	likeReq.Header.Set("Authorization", "Bearer "+session.AccessToken)
	likeRes := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(likeRes, likeReq)
	if likeRes.Code != http.StatusOK {
		t.Fatalf("like own comment failed: status=%d body=%s", likeRes.Code, likeRes.Body.String())
	}

	patchReq := httptest.NewRequest(http.MethodPatch, "/api/v1/comments/"+created.ID, strings.NewReader(`{"content":"编辑后的内容"}`))
	patchReq.Header.Set("Authorization", "Bearer "+session.AccessToken)
	patchRes := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(patchRes, patchReq)
	if patchRes.Code != http.StatusOK {
		t.Fatalf("patch comment failed: status=%d body=%s", patchRes.Code, patchRes.Body.String())
	}
	var updated commentResponse
	if err := json.Unmarshal(patchRes.Body.Bytes(), &updated); err != nil {
		t.Fatalf("unmarshal patched comment failed: %v", err)
	}
	if updated.ID != created.ID || updated.Content != "编辑后的内容" {
		t.Fatalf("unexpected patched comment: %+v", updated)
	}
	if updated.PostID != postID {
		t.Fatalf("expected post_id=%s, got %q", postID, updated.PostID)
	}
	if updated.Author.ID != session.User.ID || updated.Author.Nickname != "评论编辑者" {
		t.Fatalf("expected full author summary, got %+v", updated.Author)
	}
	if len(updated.Media) != 1 || updated.Media[0].ID != mediaID {
		t.Fatalf("expected media preserved after edit, got %+v", updated.Media)
	}
	if updated.CreatedAt.IsZero() {
		t.Fatal("expected created_at in patch response")
	}
	if updated.ViewerState == nil || !updated.ViewerState.HasLiked {
		t.Fatalf("expected viewer_state.has_liked=true after self-like, got %+v", updated.ViewerState)
	}
}

func TestReplyToUserDerivedFromParent(t *testing.T) {
	s := feedIntegrationServer(t)
	_, postIDs := insertFeedFixtures(t, s)
	postID := postIDs["p1"]

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	register := func(name string) auth.AuthResponse {
		session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
			Username: name + "_" + suffix,
			Password: "安全密码12345",
			Nickname: name,
		}, auth.SessionMetadata{UserAgent: "reply-target-test", IPAddress: "127.0.0.1"})
		if err != nil {
			t.Fatal(err)
		}
		return session
	}
	author := register("楼层作者")
	replier := register("回复者")
	outsider := register("无关用户")

	rootReq := httptest.NewRequest(http.MethodPost, "/api/v1/posts/"+postID+"/comments", strings.NewReader(`{"content":"根评论"}`))
	rootReq.Header.Set("Authorization", "Bearer "+author.AccessToken)
	rootReq.Header.Set("Idempotency-Key", "key-root-"+suffix)
	rootRes := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(rootRes, rootReq)
	if rootRes.Code != http.StatusCreated {
		t.Fatalf("create root comment failed: status=%d body=%s", rootRes.Code, rootRes.Body.String())
	}
	var root commentResponse
	if err := json.Unmarshal(rootRes.Body.Bytes(), &root); err != nil {
		t.Fatalf("unmarshal root comment failed: %v", err)
	}

	replyReq := httptest.NewRequest(http.MethodPost, "/api/v1/comments/"+root.ID+"/replies", strings.NewReader(fmt.Sprintf(`{"content":"伪造回复目标","reply_to_user_id":"%s"}`, outsider.User.ID)))
	replyReq.Header.Set("Authorization", "Bearer "+replier.AccessToken)
	replyReq.Header.Set("Idempotency-Key", "key-reply-"+suffix)
	replyRes := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(replyRes, replyReq)
	if replyRes.Code != http.StatusCreated {
		t.Fatalf("create reply failed: status=%d body=%s", replyRes.Code, replyRes.Body.String())
	}
	var reply commentResponse
	if err := json.Unmarshal(replyRes.Body.Bytes(), &reply); err != nil {
		t.Fatalf("unmarshal reply failed: %v", err)
	}
	if reply.ReplyToUserID == nil || *reply.ReplyToUserID != author.User.ID {
		t.Fatalf("expected reply_to_user_id derived from parent author %s, got %v", author.User.ID, reply.ReplyToUserID)
	}
	var dbReplyTo string
	if err := s.db.QueryRow(`SELECT COALESCE(reply_to_user_id, '') FROM comments WHERE id = $1`, reply.ID).Scan(&dbReplyTo); err != nil || dbReplyTo != author.User.ID {
		t.Fatalf("expected db reply_to_user_id=%s, got err=%v value=%q", author.User.ID, err, dbReplyTo)
	}
}

func TestReplyToHiddenCommentRejected(t *testing.T) {
	s := feedIntegrationServer(t)
	_, postIDs := insertFeedFixtures(t, s)
	postID := postIDs["p1"]

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	register := func(name string) auth.AuthResponse {
		session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
			Username: name + "_" + suffix,
			Password: "安全密码12345",
			Nickname: name,
		}, auth.SessionMetadata{UserAgent: "hidden-parent-test", IPAddress: "127.0.0.1"})
		if err != nil {
			t.Fatal(err)
		}
		return session
	}
	author := register("楼层作者")
	replier := register("回复者")

	rootReq := httptest.NewRequest(http.MethodPost, "/api/v1/posts/"+postID+"/comments", strings.NewReader(`{"content":"将被隐藏的评论"}`))
	rootReq.Header.Set("Authorization", "Bearer "+author.AccessToken)
	rootReq.Header.Set("Idempotency-Key", "key-hidden-root-"+suffix)
	rootRes := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(rootRes, rootReq)
	if rootRes.Code != http.StatusCreated {
		t.Fatalf("create root comment failed: status=%d body=%s", rootRes.Code, rootRes.Body.String())
	}
	var root commentResponse
	if err := json.Unmarshal(rootRes.Body.Bytes(), &root); err != nil {
		t.Fatalf("unmarshal root comment failed: %v", err)
	}
	if _, err := s.db.Exec(`UPDATE comments SET publication_status = 'hidden' WHERE id = $1`, root.ID); err != nil {
		t.Fatal(err)
	}

	replyReq := httptest.NewRequest(http.MethodPost, "/api/v1/comments/"+root.ID+"/replies", strings.NewReader(`{"content":"不应成功"}`))
	replyReq.Header.Set("Authorization", "Bearer "+replier.AccessToken)
	replyReq.Header.Set("Idempotency-Key", "key-hidden-reply-"+suffix)
	replyRes := httptest.NewRecorder()
	NewHandler(s.db).ServeHTTP(replyRes, replyReq)
	if replyRes.Code != http.StatusNotFound {
		t.Fatalf("expected reply to hidden comment to be rejected with 404, got status=%d body=%s", replyRes.Code, replyRes.Body.String())
	}
	var replyCount int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM comments WHERE author_id = $1 AND deleted_at IS NULL`, replier.User.ID).Scan(&replyCount); err != nil || replyCount != 0 {
		t.Fatalf("expected no reply persisted, got err=%v count=%d", err, replyCount)
	}
}

// 推荐严格限定管理员人工源：
// 普通公开帖 A、管理员推荐 B (pos=2)、管理员推荐 C (pos=1)
// 请求 sort=recommended：必须为 [C, B]，绝对不能出现 A；
// 移除 C 后，再次请求只剩 [B]。
func TestFeedRecommendedStrictAdminOnly(t *testing.T) {
	s := feedIntegrationServer(t)
	communityID, ids := insertFeedFixtures(t, s)

	postA := ids["p1"]
	postB := ids["p2"]
	postC := ids["p3"]

	// 将 postB 加入推荐，位次 2
	if _, err := s.db.Exec(`
		INSERT INTO home_recommendations (post_id, recommended_by, position, recommended_at)
		VALUES ($1, (SELECT author_id FROM posts WHERE id = $1), 2, now() - interval '1 hour')`, postB); err != nil {
		t.Fatal(err)
	}

	// 将 postC 加入推荐，位次 1
	if _, err := s.db.Exec(`
		INSERT INTO home_recommendations (post_id, recommended_by, position, recommended_at)
		VALUES ($1, (SELECT author_id FROM posts WHERE id = $1), 1, now())`, postC); err != nil {
		t.Fatal(err)
	}

	// 1. 获取推荐 Feed，必须只有 C 和 B，且按 position 正序排，绝无未被推荐的 A
	got := fetchFeedIDs(t, s, "recommended", communityID)
	requireFeedOrder(t, got, []string{postC, postB}, "recommended: initial")
	if slices.Contains(got, postA) {
		t.Fatalf("未人工推荐的帖子 A (%s) 不应出现在推荐流中: %v", postA, got)
	}

	// 2. 从推荐中移除 C
	if _, err := s.db.Exec(`DELETE FROM home_recommendations WHERE post_id = $1`, postC); err != nil {
		t.Fatal(err)
	}

	// 3. 再次获取推荐 Feed，必须只剩 B
	gotAfterDelete := fetchFeedIDs(t, s, "recommended", communityID)
	requireFeedOrder(t, gotAfterDelete, []string{postB}, "recommended: after delete C")
	if slices.Contains(gotAfterDelete, postC) {
		t.Fatalf("已被移除推荐的帖子 C (%s) 仍出现在推荐流中: %v", postC, gotAfterDelete)
	}
}
