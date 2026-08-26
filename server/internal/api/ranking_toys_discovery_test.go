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
		"category", "segments", "search_rank",
	}
	toyRows := sqlmock.NewRows(toyCols).
		AddRow("toy-butter-2", 1, "黄油小姐 二代", "COC", 2025, "奶香软糯", `["奶香材质","软糯包裹"]`, "thumb_01.webp", 401, 1479, 17, "cup", `["beginner"]`, 100.0)

	postCols := []string{"id", "title", "content_preview", "community_id", "community_name", "created_at", "rank"}
	postRows := sqlmock.NewRows(postCols).
		AddRow("post-1", "如何选择黄油小姐二代？", "正文预览", "c-1", "杯子交流", time.Now().UTC(), 50.0)

	userCols := []string{"id", "username", "nickname", "created_at", "rank"}
	userRows := sqlmock.NewRows(userCols)

	commCols := []string{"id", "slug", "name", "description", "post_count", "follower_count", "sort_order", "rank"}
	commRows := sqlmock.NewRows(commCols)

	mock.ExpectQuery(`(?s)SELECT t.id, t.rank, t.name.*FROM ranking_toys t.*LIMIT \$2`).
		WithArgs("黄油", 21).
		WillReturnRows(toyRows)

	mock.ExpectQuery(`(?s)SELECT p.id, p.title.*FROM posts p.*LIMIT \$2`).
		WithArgs("黄油", 21).
		WillReturnRows(postRows)

	mock.ExpectQuery(`(?s)SELECT u.id, u.username.*FROM users u.*LIMIT \$2`).
		WithArgs("黄油", 21).
		WillReturnRows(userRows)

	mock.ExpectQuery(`(?s)SELECT c.id, c.slug.*FROM communities c.*LIMIT \$2`).
		WithArgs("黄油", 21).
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
		"category", "segments", "wanted", "owned", "rating",
	}
	toyRows := sqlmock.NewRows(toyCols).
		AddRow("toy-butter-2", 1, "黄油小姐 二代", "COC", 2025, "简介", `["标签"]`, "hero.webp", 401, 870, 10, "cup", `["beginner"]`, false, false, nil)

	mock.ExpectQuery(`(?s)SELECT t.id, t.rank.*FROM ranking_toys t.*WHERE t.id = \$1`).
		WithArgs("toy-butter-2", "").
		WillReturnRows(toyRows)

	commentCols := []string{
		"id", "author_id", "username", "nickname", "level", "content",
		"like_count", "has_liked", "created_at", "root_id", "parent_id", "reply_to_user_id", "reply_count", "author_rating",
	}
	commentRows := sqlmock.NewRows(commentCols).
		AddRow("c-1", "u-1", "tester", "评测君", 3, "手感很好", 5, false, time.Now().UTC(), nil, nil, nil, 0, 9)

	mock.ExpectQuery(`(?s)SELECT c.id, c.author_id.*FROM ranking_toy_comments c.*WHERE c.toy_id = \$1`).
		WithArgs("toy-butter-2", "").
		WillReturnRows(commentRows)

	distCols := []string{"rating", "count"}
	distRows := sqlmock.NewRows(distCols).
		AddRow(10, 6).
		AddRow(9, 3).
		AddRow(8, 1)

	mock.ExpectQuery(`(?s)SELECT rating, COUNT\(\*\).*FROM ranking_toy_user_states.*WHERE toy_id = \$1`).
		WithArgs("toy-butter-2").
		WillReturnRows(distRows)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/ranking/toys/toy-butter-2", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("ranking toy response code=%d body=%s", res.Code, res.Body.String())
	}

	var detail struct {
		ID                 string                 `json:"id"`
		Name               string                 `json:"name"`
		Category           string                 `json:"category"`
		Segments           []string               `json:"segments"`
		RatingDistribution map[string]int         `json:"rating_distribution"`
		Comments           []map[string]any       `json:"comments"`
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
