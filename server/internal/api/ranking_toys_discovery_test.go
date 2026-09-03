package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestSearchReturnsToysInAllAndToysMode(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	toyCols := []string{
		"id", "rank", "name", "merchant", "release_year", "description",
		"tags", "asset_key", "want_count", "rating_total_centi", "rating_count",
		"category", "segments",
		"cover_media_id", "cover_object_key", "hero_media_id", "hero_object_key", "coupon_url", "source_url", "source_provider",
		"search_rank",
	}
	toyRows := sqlmock.NewRows(toyCols).
		AddRow("toy-butter-2", 1, "黄油小姐 二代", "COC", 2025, "奶香软糯", `["奶香材质","软糯包裹"]`, "thumb_01.webp", 401, 1479, 17, "cup", `["beginner"]`, "", "", "", "", "", "", "", 100.0)

	postCols := []string{"id", "author_id", "username", "author_name", "author_level", "title", "content_preview", "community_id", "community_name", "created_at", "comment_count", "like_count", "view_count", "rank"}
	postRows := sqlmock.NewRows(postCols).
		AddRow("post-1", "u-1", "tester", "评测君", 4, "如何选择黄油小姐二代？", "正文预览", "c-1", "杯子交流", time.Now().UTC(), 18, 6, 98, 50.0)

	userCols := []string{"id", "username", "nickname", "created_at", "rank"}
	userRows := sqlmock.NewRows(userCols)

	commCols := []string{"id", "slug", "name", "description", "post_count", "follower_count", "sort_order", "rank"}
	commRows := sqlmock.NewRows(commCols)

	mock.ExpectQuery(`(?s)SELECT t.id, t.rank, t.name.*FROM ranking_toys t.*LIMIT \$2`).
		WithArgs("黄油", 4).
		WillReturnRows(toyRows)

	mock.ExpectQuery(`(?s)SELECT p.id, p.author_id.*p.title.*FROM posts p.*LIMIT \$2`).
		WithArgs("黄油", 6).
		WillReturnRows(postRows)

	mock.ExpectQuery(`(?s)SELECT u.id, u.username.*FROM users u.*LIMIT \$2`).
		WithArgs("黄油", 4).
		WillReturnRows(userRows)

	mock.ExpectQuery(`(?s)SELECT c.id, c.slug.*FROM communities c.*LIMIT \$2`).
		WithArgs("黄油", 4).
		WillReturnRows(commRows)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/search?q=%E9%BB%84%E6%B2%B9&type=all", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("search response code=%d body=%s", res.Code, res.Body.String())
	}

	var body struct {
		Toys        []map[string]any `json:"toys"`
		Posts       []map[string]any `json:"posts"`
		Users       []map[string]any `json:"users"`
		Communities []map[string]any `json:"communities"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}

	if len(body.Toys) != 1 || body.Toys[0]["name"] != "黄油小姐 二代" || body.Toys[0]["category"] != "cup" {
		t.Fatalf("unexpected toys response: %#v", body.Toys)
	}
	if len(body.Posts) != 1 || !strings.Contains(body.Posts[0]["title"].(string), "黄油小姐") {
		t.Fatalf("unexpected posts response: %#v", body.Posts)
	}
	if body.Posts[0]["author_name"] != "评测君" || body.Posts[0]["comment_count"] != float64(18) || body.Posts[0]["view_count"] != float64(98) {
		t.Fatalf("search post metadata missing: %#v", body.Posts[0])
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestGetRankingToyReturnsRatingDistribution(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	toyCols := []string{
		"id", "rank", "name", "merchant", "release_year", "description",
		"tags", "asset_key", "want_count", "rating_total_centi", "rating_count",
		"category", "segments", "cover_media_id", "cover_object_key", "hero_media_id", "hero_object_key", "coupon_url", "source_url", "source_provider",
		"wanted", "owned", "rating",
	}
	toyRows := sqlmock.NewRows(toyCols).
		AddRow("toy-butter-2", 1, "黄油小姐 二代", "COC", 2025, "简介", `["标签"]`, "hero.webp", 401, 870, 10, "cup", `["beginner"]`, "", "", "", "", "", "", "", false, false, nil)

	mock.ExpectQuery(`(?s)SELECT t.id, t.rank.*FROM ranking_toys t.*WHERE t.id = \$1`).
		WithArgs("toy-butter-2", "").
		WillReturnRows(toyRows)

	commentCols := []string{
		"id", "author_id", "username", "nickname", "level", "content",
		"like_count", "has_liked", "created_at", "root_id", "parent_id", "reply_to_user_id", "reply_count", "author_rating", "media",
		"avatar_media_id", "avatar_object_key",
	}
	commentRows := sqlmock.NewRows(commentCols).
		AddRow("c-1", "u-1", "tester", "评测君", 3, "手感很好", 5, false, time.Now().UTC(), nil, nil, nil, 0, 9, nil, "", "")

	mock.ExpectQuery(`(?s)SELECT c.id, c.author_id.*FROM ranking_toy_comments c.*WHERE c.toy_id = \$1`).
		WithArgs("toy-butter-2", "", 21).
		WillReturnRows(commentRows)

	distCols := []string{"rating", "count"}
	distRows := sqlmock.NewRows(distCols).
		AddRow(10, 6).
		AddRow(9, 3).
		AddRow(8, 1)

	mock.ExpectQuery(`(?s)SELECT score, rating_count.*FROM ranking_toy_rating_distribution.*WHERE toy_id = \$1`).
		WithArgs("toy-butter-2").
		WillReturnRows(distRows)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/ranking/toys/toy-butter-2", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("ranking toy response code=%d body=%s", res.Code, res.Body.String())
	}

	var detail struct {
		ID                 string           `json:"id"`
		Name               string           `json:"name"`
		Category           string           `json:"category"`
		Segments           []string         `json:"segments"`
		RatingDistribution map[string]int   `json:"rating_distribution"`
		Comments           []map[string]any `json:"comments"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &detail); err != nil {
		t.Fatal(err)
	}

	if detail.Category != "cup" || len(detail.Segments) != 1 || detail.Segments[0] != "beginner" {
		t.Fatalf("unexpected category/segments: category=%s segments=%v", detail.Category, detail.Segments)
	}
	if detail.RatingDistribution["10"] != 6 || detail.RatingDistribution["9"] != 3 || detail.RatingDistribution["8"] != 1 || detail.RatingDistribution["1"] != 0 {
		t.Fatalf("unexpected rating distribution: %#v", detail.RatingDistribution)
	}
	if len(detail.Comments) != 1 || detail.Comments[0]["author_rating"] != float64(9) {
		t.Fatalf("unexpected comment author rating: %#v", detail.Comments)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestListRankingToyCommentsPaginatesRootsOnly(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(`SELECT id FROM ranking_toys WHERE id = \$1 AND active = true`).
		WithArgs("toy-1").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("toy-1"))
	commentRows := sqlmock.NewRows([]string{
		"id", "author_id", "username", "nickname", "level", "content",
		"like_count", "has_liked", "created_at", "root_id", "parent_id", "reply_to_user_id", "reply_count", "author_rating", "media",
		"avatar_media_id", "avatar_object_key",
	}).
		AddRow("root-1", "u-1", "u1", "用户1", 2, "root one", 8, false, time.Date(2026, 8, 27, 10, 0, 0, 0, time.UTC), "root-1", nil, nil, 2, 9, nil, "", "").
		AddRow("root-2", "u-2", "u2", "用户2", 2, "root two", 3, false, time.Date(2026, 8, 27, 9, 0, 0, 0, time.UTC), "root-2", nil, nil, 0, 8, nil, "", "")
	mock.ExpectQuery(`(?s)SELECT c.id, c.author_id.*c.parent_id IS NULL.*LIMIT \$3`).
		WithArgs("toy-1", "", 2).
		WillReturnRows(commentRows)
	previewRows := sqlmock.NewRows([]string{
		"id", "author_id", "username", "nickname", "level", "content",
		"like_count", "has_liked", "created_at", "root_id", "parent_id", "reply_to_user_id", "reply_count", "author_rating", "media",
		"avatar_media_id", "avatar_object_key",
	}).AddRow("reply-1", "u-2", "u2", "用户2", 2, "reply one", 5, false, time.Date(2026, 8, 27, 11, 0, 0, 0, time.UTC), "root-1", "root-1", nil, 0, 0, nil, "", "")
	mock.ExpectQuery(`(?s)SELECT c.id, c.author_id.*FROM.*ranking_toy_comments c.*WHERE c.toy_id = \$1.*rn <= 4`).
		WithArgs("toy-1", "", "root-1").
		WillReturnRows(previewRows)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/ranking/toys/toy-1/comments?sort=latest&limit=1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("comments response code=%d body=%s", res.Code, res.Body.String())
	}
	var body struct {
		Items      []map[string]any `json:"items"`
		NextCursor string           `json:"next_cursor"`
		HasMore    bool             `json:"has_more"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Items) != 1 || body.Items[0]["id"] != "root-1" || !body.HasMore || body.NextCursor == "" {
		t.Fatalf("unexpected root page: %#v", body)
	}
	previews, ok := body.Items[0]["reply_preview"].([]any)
	if !ok || len(previews) != 1 {
		t.Fatalf("expected 1 reply_preview in root-1, got %#v", body.Items[0]["reply_preview"])
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestListRankingToyRepliesReturnsNestedRepliesFlatAndPaginated(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT toy_id, COALESCE\(root_id, id\).*FROM ranking_toy_comments`).
		WithArgs("root-1").
		WillReturnRows(sqlmock.NewRows([]string{"toy_id", "root_id"}).AddRow("toy-1", "root-1"))
	replyRows := sqlmock.NewRows([]string{
		"id", "author_id", "username", "nickname", "level", "content",
		"like_count", "has_liked", "created_at", "root_id", "parent_id", "reply_to_user_id", "reply_count", "author_rating", "media",
		"avatar_media_id", "avatar_object_key",
	}).
		AddRow("reply-1", "u-2", "u2", "用户2", 3, "回复二级", 2, false, time.Date(2026, 8, 27, 10, 1, 0, 0, time.UTC), "root-1", "reply-0", "u-3", 1, 7, nil, "", "").
		AddRow("reply-2", "u-3", "u3", "用户3", 1, "回复三级", 1, false, time.Date(2026, 8, 27, 10, 2, 0, 0, time.UTC), "root-1", "reply-1", "u-2", 0, 6, nil, "", "")
	mock.ExpectQuery(`(?s)SELECT c.id, c.author_id.*COALESCE\(c.root_id, c.id\) = \$2.*LIMIT \$4`).
		WithArgs("toy-1", "root-1", "", 2).
		WillReturnRows(replyRows)
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM users u`).WithArgs("u-3").
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "nickname", "level", "avatar_media_id", "object_key"}).AddRow("u-3", "u3", "用户3", 1, "", ""))
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM users u`).WithArgs("u-2").
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "nickname", "level", "avatar_media_id", "object_key"}).AddRow("u-2", "u2", "用户2", 3, "", ""))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/ranking/toy-comments/root-1/replies?limit=1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("replies response code=%d body=%s", res.Code, res.Body.String())
	}
	var body struct {
		Items   []map[string]any `json:"items"`
		HasMore bool             `json:"has_more"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Items) != 1 || body.Items[0]["id"] != "reply-1" || body.Items[0]["parent_id"] != "reply-0" || !body.HasMore {
		t.Fatalf("unexpected reply page: %#v", body)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
