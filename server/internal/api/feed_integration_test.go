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
	"testing"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/database"
)

// feedIntegrationServer 打开 DATABASE_URL 指向的真实 Postgres，应用全部迁移，
// 返回可直接调用 handler 的 Server。未配置 DATABASE_URL 时跳过，保证本地
// `go test ./...` 不需要数据库。
func feedIntegrationServer(t *testing.T) *Server {
	t.Helper()
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
	if _, err := s.db.Exec(`INSERT INTO users (id, username, status) VALUES ($1, $2, 'active')`, userID, userName); err != nil {
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

// 固定三篇帖：p1 很旧零互动、p2 很新低互动、p3 一天前高互动。
// 期望排序：latest=[p2,p3,p1]（纯时间）、featured=[p3,p2,p1]（无时间衰减）、
// recommended=[p3,p2,p1]（衰减平缓，质量取胜）、hot=[p2,p3,p1]（近期爆发领先）。
func TestFeedSortsAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	communityID, ids := insertFeedFixtures(t, s)

	cases := []struct {
		sort string
		want []string
	}{
		{"latest", []string{ids["p2"], ids["p3"], ids["p1"]}},
		{"featured", []string{ids["p3"], ids["p2"], ids["p1"]}},
		{"recommended", []string{ids["p3"], ids["p2"], ids["p1"]}},
		{"hot", []string{ids["p2"], ids["p3"], ids["p1"]}},
	}
	for _, tc := range cases {
		got := fetchFeedIDs(t, s, tc.sort, communityID)
		requireFeedOrder(t, got, tc.want, tc.sort)
	}
}
