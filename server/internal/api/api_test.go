package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/platform/storage"
)


func TestAPIWithoutDatabaseReturns503(t *testing.T) {
	for _, path := range []string{"/api/v1/community-categories", "/api/v1/communities", "/api/v1/feed/latest", "/api/v1/posts/p1", "/api/v1/auth/register", "/api/v1/auth/login", "/api/v1/auth/refresh", "/api/v1/auth/logout", "/api/v1/me"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		if strings.Contains(path, "/auth/") {
			req = httptest.NewRequest(http.MethodPost, path, strings.NewReader(`{"username":"user","password":"password123"}`))
		}
		res := httptest.NewRecorder()
		NewHandler(nil).ServeHTTP(res, req)
		if res.Code != http.StatusServiceUnavailable {
			t.Fatalf("%s status = %d, want 503", path, res.Code)
		}
	}
}

func TestAuthMethodAndBearerValidation(t *testing.T) {
	db, _, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	methodReq := httptest.NewRequest(http.MethodGet, "/api/v1/auth/register", nil)
	methodRes := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(methodRes, methodReq)
	if methodRes.Code != http.StatusMethodNotAllowed {
		t.Fatalf("auth method status = %d, want 405", methodRes.Code)
	}

	meReq := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	meRes := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(meRes, meReq)
	if meRes.Code != http.StatusUnauthorized || !strings.Contains(meRes.Body.String(), `"code":"INVALID_TOKEN"`) {
		t.Fatalf("missing bearer response: status=%d body=%s", meRes.Code, meRes.Body.String())
	}
}

func TestRegisterRejectsWeakPasswordBeforeDatabaseAccess(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", strings.NewReader(`{"username":"new_user","password":"short"}`))
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusBadRequest || !strings.Contains(res.Body.String(), `"code":"INVALID_INPUT"`) {
		t.Fatalf("weak password response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestCreatePostRequiresBearerToken(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts", strings.NewReader(`{"community_id":"c1","type":"normal","title":"标题","content":"正文"}`))
	req.Header.Set("Idempotency-Key", "post-key-1")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized || !strings.Contains(res.Body.String(), `"code":"INVALID_TOKEN"`) {
		t.Fatalf("create post auth response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestCreatePostRejectsRetiredMarketType(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).AddRow("u1", "user", "active", "用户", 1, 0, "email", "", false, nil, false))

	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts", strings.NewReader(`{"community_id":"c1","type":"market","title":"旧类型","content":"不应创建","market":{"price":1,"condition":"used"}}`))
	req.Header.Set("Authorization", "Bearer access-token")
	req.Header.Set("Idempotency-Key", "market-key-1")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusGone || !strings.Contains(res.Body.String(), `"code":"FEATURE_DISABLED"`) {
		t.Fatalf("retired market response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestCreatePostWritesRevisionAndIsIdempotentByUserKey(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).WithArgs(sqlmock.AnyArg()).WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).AddRow("u1", "user", "active", "用户", 2, 100, "email", "", false, nil, false))
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT pg_advisory_xact_lock(hashtext($1 || ':' || $2))`)).WithArgs("u1", "post-key-1").WillReturnRows(sqlmock.NewRows([]string{"pg_advisory_xact_lock"}).AddRow(nil))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id FROM post_idempotency_keys WHERE user_id = $1 AND idempotency_key = $2`)).WithArgs("u1", "post-key-1").WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM communities WHERE id = $1 AND status = 'active' AND deleted_at IS NULL`)).WithArgs("c1").WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("c1"))
	mock.ExpectQuery(regexp.QuoteMeta(`INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, created_at, updated_at, published_at) VALUES ($1, $2, $3, $4, 'published', 'normal', $5, $6, $7, $7, $7) RETURNING post_status, moderation_status`)).WithArgs(sqlmock.AnyArg(), "u1", "c1", "normal", "标题", "正文", sqlmock.AnyArg()).WillReturnRows(sqlmock.NewRows([]string{"post_status", "moderation_status"}).AddRow("published", "normal"))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO post_revisions (id, post_id, editor_id, community_id, type, title, content, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`)).WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg(), "u1", "c1", "normal", "标题", "正文", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO post_idempotency_keys (user_id, idempotency_key, post_id, created_at) VALUES ($1, $2, $3, $4)`)).WithArgs("u1", "post-key-1", sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery(`(?s)SELECT COALESCE\(up\.experience, 0\).*FROM users u`).WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"experience", "account_type"}).AddRow(100, "email"))
	mock.ExpectQuery(`(?s)SELECT experience_after.*FROM experience_transactions`).WithArgs("u1", sqlmock.AnyArg()).WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`(?s)SELECT count\(\*\).*FROM experience_transactions`).WithArgs("u1", "post").WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))
	mock.ExpectExec(`(?s)UPDATE user_profiles.*SET experience = \$1, level = \$2`).WithArgs(int64(120), 2, "u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`(?s)INSERT INTO experience_transactions`).WithArgs(sqlmock.AnyArg(), "u1", "post", int64(20), int64(120), "发布帖子", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO outbox_events (id, event_type, aggregate_type, aggregate_id, payload, status, available_at, created_at)
		VALUES ($1, $2, $3, $4, $5::jsonb, 'pending', $6, $6)`)).WithArgs(sqlmock.AnyArg(), "post.created", "post", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts", strings.NewReader(`{"community_id":"c1","type":"normal","title":"标题","content":"正文"}`))
	req.Header.Set("Authorization", "Bearer access-token")
	req.Header.Set("Idempotency-Key", "post-key-1")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusCreated || !strings.Contains(res.Body.String(), `"publication_status":"published"`) {
		t.Fatalf("create post response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestMediaUploadTokenRequiresBearerToken(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/media/upload-token", strings.NewReader(`{"file_name":"a.png","mime_type":"image/png","size":10}`))
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized || !strings.Contains(res.Body.String(), `"code":"INVALID_TOKEN"`) {
		t.Fatalf("media auth response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

type testMediaStorage struct {
	storage.UnavailableMediaStorage
}

func (testMediaStorage) SignUpload(_ context.Context, assetID, _ string, _ string, _ time.Time) (string, error) {
	return "https://upload.example/" + assetID, nil
}

func (testMediaStorage) VerifyUploaded(context.Context, *storage.MediaAsset) error { return nil }

func TestMediaUploadTokenCreatesPendingAssetWithSignedURL(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).WithArgs(sqlmock.AnyArg()).WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).AddRow("u1", "user", "active", "User", 1, 0, "email", "", false, nil, false))
	checksum := strings.Repeat("a", 64)
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO media_assets (id, owner_id, object_key, original_name, mime_type, width, height, size, sha256, status, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'pending', $10, $10)`)).WithArgs(sqlmock.AnyArg(), "u1", sqlmock.AnyArg(), "a.png", "image/png", 100, 80, int64(10), checksum, sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))

	req := httptest.NewRequest(http.MethodPost, "/api/v1/media/upload-token", strings.NewReader(`{"file_name":"a.png","mime_type":"image/png","width":100,"height":80,"size":10,"sha256":"`+checksum+`"}`))
	req.Header.Set("Authorization", "Bearer access-token")
	res := httptest.NewRecorder()
	NewHandlerWithMedia(db, nil, testMediaStorage{}).ServeHTTP(res, req)
	if res.Code != http.StatusCreated || !strings.Contains(res.Body.String(), `"status":"pending"`) || !strings.Contains(res.Body.String(), `"upload_url":"https://upload.example/`) {
		t.Fatalf("media upload response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestCreateCommentRequiresBearerToken(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts/p1/comments", strings.NewReader(`{"content":"评论"}`))
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized || !strings.Contains(res.Body.String(), `"code":"INVALID_TOKEN"`) {
		t.Fatalf("comment auth response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestListCommentsReturnsStableFloors(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	created := time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL`)).WithArgs("p1").WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("p1"))
	mock.ExpectQuery(`(?s)SELECT COUNT\(\*\)\s*FROM \(.*WHERE 1 = 1$`).WithArgs("p1").WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(2))
	mock.ExpectQuery(`(?s)SELECT t\.id, t\.post_id.*ORDER BY t\.floor_no ASC, t\.id ASC OFFSET 0 LIMIT 1$`).WithArgs("p1").WillReturnRows(sqlmock.NewRows([]string{
		"id", "post_id", "author_id", "username", "nickname", "level", "object_key", "content",
		"like_count", "dislike_count", "reply_count", "created_at", "updated_at", "floor_no",
		"root_id", "parent_id", "reply_to_user_id", "sticker_id", "publication_status", "has_liked", "has_disliked",
	}).AddRow("cm1", "p1", "u1", "user", "User", 1, "", "第一条", 0, 0, 0, created, created, 1, "cm1", "", "", "", "published", false, false))
	mock.ExpectQuery(`(?s)ROW_NUMBER\(\) OVER \(PARTITION BY c\.root_id.*ORDER BY t\.root_id ASC, t\.rn ASC$`).WithArgs("cm1").WillReturnRows(sqlmock.NewRows([]string{
		"id", "post_id", "author_id", "username", "nickname", "level", "object_key", "content",
		"like_count", "dislike_count", "reply_count", "created_at", "updated_at", "floor_no",
		"root_id", "parent_id", "reply_to_user_id", "sticker_id", "publication_status", "has_liked", "has_disliked",
	}))
	mock.ExpectQuery(`(?s)SELECT cm\.comment_id, ma\.id.*FROM comment_media cm`).WithArgs("cm1").WillReturnRows(sqlmock.NewRows([]string{"comment_id", "id", "mime_type", "width", "height", "original_name", "object_key"}))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/posts/p1/comments?limit=1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"has_more":true`) || !strings.Contains(res.Body.String(), `"total":2`) || !strings.Contains(res.Body.String(), `"floor":1`) {
		t.Fatalf("comments response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestProfileCommentsReturnsAuthoredComments(t *testing.T) {
	query, _, err := profileCommentListQuery("u1", "", 1)
	if err != nil || !strings.Contains(query, "c.author_id = $1") {
		t.Fatalf("profile comments query must query user authored comments: %s", query)
	}
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	created := time.Date(2026, 8, 24, 23, 20, 0, 0, time.UTC)
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).AddRow("u1", "user", "active", "用户", 1, 0, "email", "", false, nil, false))
	mock.ExpectQuery(`(?s)SELECT c\.id, p\.id, p\.title.*FROM comments c.*ORDER BY c\.created_at DESC, c\.id DESC LIMIT \$2`).
		WithArgs("u1", 2).
		WillReturnRows(sqlmock.NewRows([]string{"comment_id", "id", "title", "content_preview", "community_id", "community_name", "comment_count", "like_count", "bookmark_count", "published_at", "activity_at"}).
			AddRow("c1", "post-1", "帖子一", "我写的评论一", "c1", "大型拆箱", int64(3), int64(2), int64(1), created.Add(-time.Hour), created).
			AddRow("c2", "post-2", "帖子二", "我写的评论二", "c1", "大型拆箱", int64(1), int64(0), int64(0), created.Add(-2*time.Hour), created.Add(-time.Minute)))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/me/comments?limit=1", nil)
	req.Header.Set("Authorization", "Bearer access-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"comment_id":"c1"`) || !strings.Contains(res.Body.String(), `"id":"post-1"`) || !strings.Contains(res.Body.String(), `"activity_at":"2026-08-24T23:20:00Z"`) || !strings.Contains(res.Body.String(), `"has_more":true`) {
		t.Fatalf("profile comments response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestPublicUserPostsExposeRealPostCounts(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	created := time.Date(2026, 8, 24, 20, 0, 0, 0, time.UTC)
	mock.ExpectQuery(`(?s)SELECT p\.id, p\.title.*p\.view_count.*FROM posts p.*p\.author_id = \$1.*LIMIT \$2`).
		WithArgs("u1", 2).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "title", "content", "community_id", "community_name",
			"comment_count", "like_count", "bookmark_count", "view_count", "created_at",
		}).AddRow("post-1", "真实帖子", "正文", "c1", "评测区", 5, 37, 2, 321, created))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/users/u1/posts?limit=1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK ||
		!strings.Contains(res.Body.String(), `"like_count":37`) ||
		!strings.Contains(res.Body.String(), `"view_count":321`) {
		t.Fatalf("public user posts response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestStoreProductsOrdersByRedeemedCount(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(`(?s)SELECT p\.id, p\.name.*COUNT\(o\.id\).*ORDER BY redeemed_count DESC`).
		WithArgs().
		WillReturnRows(sqlmock.NewRows([]string{"id", "name", "description", "emoji", "points", "color", "redeemed_count"}).
			AddRow("p1", "校园徽章", "纪念品", "🏅", int64(120), 16766842, int64(42)))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/store/products", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"redeemed_count":42`) {
		t.Fatalf("store products response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestTogglePostLikeRequiresBearerToken(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	req := httptest.NewRequest(http.MethodPut, "/api/v1/posts/p1/like", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized || !strings.Contains(res.Body.String(), `"code":"INVALID_TOKEN"`) {
		t.Fatalf("like auth response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestPostLikeIsIdempotentAndUpdatesCountOnlyAfterNewRelation(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for index, inserted := range []int64{1, 0} {
		mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).WithArgs(sqlmock.AnyArg()).WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).AddRow("u1", "user", "active", "User", 1, 0, "email", "", false, nil, false))
		mock.ExpectBegin()
		mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL FOR UPDATE`)).WithArgs("p1").WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("p1"))
		mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO post_reactions (post_id, user_id, reaction_type) VALUES ($1, $2, $3) ON CONFLICT (post_id, user_id, reaction_type) DO NOTHING`)).WithArgs("p1", "u1", "like").WillReturnResult(sqlmock.NewResult(1, inserted))
		if inserted == 1 {
			mock.ExpectExec(regexp.QuoteMeta(`UPDATE posts SET like_count = GREATEST(like_count + 1, 0), updated_at = now() WHERE id = $1`)).WithArgs("p1").WillReturnResult(sqlmock.NewResult(1, 1))
			mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id FROM posts WHERE id = $1`)).WithArgs("p1").WillReturnRows(sqlmock.NewRows([]string{"author_id"}).AddRow("u2"))
			mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO notifications (id, user_id, type, actor_id, target_type, target_id, is_read, created_at)
				VALUES ($1, $2, $3, $4, $5, $6, false, $7)`)).WithArgs(sqlmock.AnyArg(), "u2", "like", "u1", "post", "p1", sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
			mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO outbox_events (id, event_type, aggregate_type, aggregate_id, payload, status, available_at, created_at)
				VALUES ($1, $2, $3, $4, $5::jsonb, 'pending', $6, $6)`)).WithArgs(sqlmock.AnyArg(), "notification.created", "notification", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
		}
		mock.ExpectCommit()
		req := httptest.NewRequest(http.MethodPut, "/api/v1/posts/p1/like", nil)
		req.Header.Set("Authorization", "Bearer access-token")
		res := httptest.NewRecorder()
		NewHandler(db).ServeHTTP(res, req)
		if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"active":true`) {
			t.Fatalf("like attempt %d: status=%d body=%s", index, res.Code, res.Body.String())
		}
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestPlatformWriteAndNotificationRoutesRequireAuthentication(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	cases := []struct {
		method string
		path   string
		body   string
	}{
		{http.MethodGet, "/api/v1/notifications", ""},
		{http.MethodPost, "/api/v1/reports", `{"target_type":"post","target_id":"p1","reason_code":"spam"}`},
		{http.MethodPut, "/api/v1/users/u2/block", ""},
		{http.MethodPatch, "/api/v1/notifications/n1/read", ""},
		{http.MethodGet, "/api/v1/moderation/cases", ""},
	}
	for _, item := range cases {
		req := httptest.NewRequest(item.method, item.path, strings.NewReader(item.body))
		res := httptest.NewRecorder()
		NewHandler(db).ServeHTTP(res, req)
		if res.Code != http.StatusUnauthorized || !strings.Contains(res.Body.String(), `"code":"INVALID_TOKEN"`) {
			t.Fatalf("%s %s response: status=%d body=%s", item.method, item.path, res.Code, res.Body.String())
		}
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestNotificationReadAllPOSTRouteRequiresAuthentication(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/notifications/read-all", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized || !strings.Contains(res.Body.String(), `"code":"INVALID_TOKEN"`) {
		t.Fatalf("notification read-all response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestAccountDeletionRouteRequiresAuthentication(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	req := httptest.NewRequest(http.MethodDelete, "/api/v1/me", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized || !strings.Contains(res.Body.String(), `"code":"INVALID_TOKEN"`) {
		t.Fatalf("account deletion response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestHomeRouteRequiresDatabase(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/home", nil)
	res := httptest.NewRecorder()
	NewHandler(nil).ServeHTTP(res, req)
	if res.Code != http.StatusServiceUnavailable {
		t.Fatalf("home status = %d, want 503", res.Code)
	}
}

func TestHomeReturnsDynamicSections(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id, slug, name, description, member_count, follower_count, post_count
		FROM communities
		WHERE status = 'active' AND deleted_at IS NULL
		ORDER BY sort_order ASC, post_count DESC, id ASC
		LIMIT 8`)).WillReturnRows(sqlmock.NewRows([]string{"id", "slug", "name", "description", "member_count", "follower_count", "post_count"}).AddRow("c1", "campus", "校园", "交流", 10, 20, 30))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT p.id, p.title, LEFT(p.content, 200), p.community_id, c.name,
		       p.like_count, p.comment_count, p.published_at
		FROM posts p`)).WillReturnRows(sqlmock.NewRows([]string{"id", "title", "content", "community_id", "name", "like_count", "comment_count", "published_at"}).AddRow("p1", "标题", "正文", "c1", "校园", 3, 2, time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/home", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"communities"`) || !strings.Contains(res.Body.String(), `"featured"`) || !strings.Contains(res.Body.String(), `"campus"`) {
		t.Fatalf("home response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestSearchRejectsEmptyQueryBeforeDatabaseAccess(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/search?q=", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusBadRequest || !strings.Contains(res.Body.String(), `"code":"INVALID_QUERY"`) {
		t.Fatalf("search response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestListCommunities(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(`(?s)SELECT id, category_id.*FROM communities`).WithArgs("category-campus", "active").WillReturnRows(sqlmock.NewRows([]string{"id", "category_id", "slug", "name", "description", "avatar", "banner", "visibility", "join_policy", "status", "member_count", "follower_count", "post_count", "sort_order"}).AddRow("c1", "cat1", "campus", "校园", "交流", "", "", "public", "open", "active", 1, 2, 3, 1))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/communities?category_id=category-campus&status=active", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"id":"c1"`) {
		t.Fatalf("communities response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestLatestFeedUsesStableCursorAndReturnsNextCursor(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	created := time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{"id", "author_id", "username", "nickname", "community_id", "slug", "community_name", "type", "title", "content", "comment_count", "like_count", "bookmark_count", "share_count", "view_count", "created_at", "updated_at", "published_at", "rec_position", "rec_at", "last_comment_at", "activity_at"}).
		AddRow("p2", "u1", "user", "用户", "c1", "campus", "校园", "normal", "第二条", "正文", 2, 3, 0, 0, 5, created, created, created, nil, nil, nil, created).
		AddRow("p1", "u1", "user", "用户", "c1", "campus", "校园", "normal", "第一条", "正文", 1, 2, 0, 0, 4, created.Add(-time.Minute), created.Add(-time.Minute), created.Add(-time.Minute), nil, nil, nil, created.Add(-time.Minute))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT CURRENT_TIMESTAMP`)).
		WillReturnRows(sqlmock.NewRows([]string{"current_timestamp"}).AddRow(created))
	mock.ExpectQuery(`(?s)SELECT p.id, p.author_id.*ORDER BY.*LIMIT \$2`).WithArgs(created, 2).WillReturnRows(rows)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/feed/latest?limit=1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK || !strings.Contains(res.Body.String(), `"has_more":true`) || !strings.Contains(res.Body.String(), `"next_cursor":"`) {
		t.Fatalf("feed response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestLatestFeedRejectsInvalidLatestBy(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	req := httptest.NewRequest(http.MethodGet, "/api/v1/feed/latest?latest_by=abcdef", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusBadRequest || !strings.Contains(res.Body.String(), `"code":"INVALID_LATEST_ORDER"`) {
		t.Fatalf("invalid latest_by status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestGetPostHidesModeratedRows(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	created := time.Date(2026, 8, 22, 12, 0, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{"id", "author_id", "username", "nickname", "community_id", "slug", "community_name", "type", "title", "content", "comment_count", "like_count", "bookmark_count", "share_count", "view_count", "created_at", "updated_at", "published_at", "publication_status", "moderation_status", "deleted_at"}).AddRow("p1", "u1", "user", "用户", "c1", "campus", "校园", "normal", "标题", "正文", 0, 0, 0, 0, 1, created, created, created, "published", "hidden", nil)
	mock.ExpectQuery(`(?s)SELECT p.id, p.author_id.*WHERE p.id = \$1`).WithArgs("p1").WillReturnRows(rows)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/posts/p1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusNotFound {
		t.Fatalf("hidden post status = %d, want 404", res.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestAPIUsesDatabaseErrorsAsInternalError(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery(regexp.QuoteMeta("SELECT id, category_id")).WillReturnError(sql.ErrConnDone)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/communities", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusInternalServerError || !strings.Contains(res.Body.String(), `"code":"INTERNAL_ERROR"`) {
		t.Fatalf("db error response: status=%d body=%s", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestCreateCommentValidationRejectsEmpty(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// 1. 未认证且空内容 -> 401
	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts/p1/comments", strings.NewReader(`{"content":""}`))
	req.Header.Set("Idempotency-Key", "test-key-1")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 on unauthenticated comment create, got %d", res.Code)
	}

	// 2. 已认证但空内容且无附件 -> 400
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).
			AddRow("u1", "user", "active", "用户", 1, 0, "email", "test@test.com", true, time.Now(), false))
	mock.ExpectQuery(`(?s)SELECT ends_at FROM restrictions WHERE user_id = \$1 AND restriction_type = 'mute'`).
		WithArgs("u1").
		WillReturnError(sql.ErrNoRows)

	req = httptest.NewRequest(http.MethodPost, "/api/v1/posts/p1/comments", strings.NewReader(`{"content":""}`))
	req.Header.Set("Authorization", "Bearer valid-token")
	req.Header.Set("Idempotency-Key", "test-key-2")
	res = httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 on authenticated empty comment without attachments, got %d", res.Code)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}


func TestCreateCommentEnforcesAttachmentConstraints(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	expectAuth := func() {
		mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
			WithArgs(sqlmock.AnyArg()).
			WillReturnRows(sqlmock.NewRows([]string{"id", "username", "status", "nickname", "level", "experience", "account_type", "email", "email_verified", "email_verified_at", "has_password"}).
				AddRow("u1", "user", "active", "用户", 1, 0, "email", "test@test.com", true, time.Now(), false))
		mock.ExpectQuery(`(?s)SELECT ends_at FROM restrictions WHERE user_id = \$1 AND restriction_type = 'mute'`).
			WithArgs("u1").
			WillReturnError(sql.ErrNoRows)
	}

	// 1. 超过 9 张图片被拒绝
	expectAuth()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts/p1/comments", strings.NewReader(`{"media_ids":["m1","m2","m3","m4","m5","m6","m7","m8","m9","m10"]}`))
	req.Header.Set("Authorization", "Bearer valid-token")
	req.Header.Set("Idempotency-Key", "k-max-media")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 when media_ids > 9, got %d", res.Code)
	}

	// 2. 图片与贴纸同时提交被拒绝（互斥约束）
	expectAuth()
	req = httptest.NewRequest(http.MethodPost, "/api/v1/posts/p1/comments", strings.NewReader(`{"media_ids":["m1"],"sticker_id":"mf_01"}`))
	req.Header.Set("Authorization", "Bearer valid-token")
	req.Header.Set("Idempotency-Key", "k-mutex")
	res = httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 when both media and sticker are present, got %d", res.Code)
	}

	// 3. 非图片 MIME 类型被拒绝
	expectAuth()
	mock.ExpectQuery(`(?s)SELECT owner_id, status, mime_type FROM media_assets WHERE id = \$1 AND deleted_at IS NULL`).
		WithArgs("m_video").
		WillReturnRows(sqlmock.NewRows([]string{"owner_id", "status", "mime_type"}).AddRow("u1", "ready", "video/mp4"))

	req = httptest.NewRequest(http.MethodPost, "/api/v1/posts/p1/comments", strings.NewReader(`{"media_ids":["m_video"]}`))
	req.Header.Set("Authorization", "Bearer valid-token")
	req.Header.Set("Idempotency-Key", "k-video-mime")
	res = httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 when media is video/mp4, got %d", res.Code)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestListCommentsReturnsImageAndStickerAttachments(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	created := time.Date(2026, 8, 29, 10, 0, 0, 0, time.UTC)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL`)).
		WithArgs("p1").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("p1"))

	mock.ExpectQuery(`(?s)SELECT COUNT\(\*\)\s*FROM \(.*WHERE 1 = 1$`).
		WithArgs("p1").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(2))

	mock.ExpectQuery(`(?s)SELECT t\.id, t\.post_id.*ORDER BY t\.floor_no ASC, t\.id ASC OFFSET 0 LIMIT 10$`).
		WithArgs("p1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "post_id", "author_id", "username", "nickname", "level", "object_key", "content",
			"like_count", "dislike_count", "reply_count", "created_at", "updated_at", "floor_no",
			"root_id", "parent_id", "reply_to_user_id", "sticker_id", "publication_status", "has_liked", "has_disliked",
		}).
			AddRow("cm_img", "p1", "u1", "user1", "用户1", 1, "", "", 0, 0, 0, created, created, 1, "cm_img", "", "", "", "published", false, false).
			AddRow("cm_stk", "p1", "u2", "user2", "用户2", 1, "", "", 0, 0, 0, created.Add(time.Minute), created.Add(time.Minute), 2, "cm_stk", "", "", "mf_01", "published", false, false))

	mock.ExpectQuery(`(?s)ROW_NUMBER\(\) OVER \(PARTITION BY c\.root_id.*ORDER BY t\.root_id ASC, t\.rn ASC$`).
		WithArgs("cm_img", "cm_stk").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "post_id", "author_id", "username", "nickname", "level", "object_key", "content",
			"like_count", "dislike_count", "reply_count", "created_at", "updated_at", "floor_no",
			"root_id", "parent_id", "reply_to_user_id", "sticker_id", "publication_status", "has_liked", "has_disliked",
		}))

	mock.ExpectQuery(`(?s)SELECT cm\.comment_id, ma\.id.*FROM comment_media cm.*JOIN media_assets ma`).
		WithArgs("cm_img", "cm_stk").
		WillReturnRows(sqlmock.NewRows([]string{"comment_id", "id", "mime_type", "width", "height", "original_name", "object_key"}).
			AddRow("cm_img", "m1", "image/png", 1024, 768, "img.png", "media/img.png"))

	mock.ExpectQuery(`(?s)SELECT mv\.media_id, mv\.variant, mv\.object_key, mv\.mime_type, mv\.width, mv\.height, mv\.size_bytes FROM media_variants mv`).
		WithArgs("m1").
		WillReturnRows(sqlmock.NewRows([]string{"media_id", "variant", "object_key", "mime_type", "width", "height", "size_bytes"}).
			AddRow("m1", "thumb", "media/img_thumb.png", "image/png", 320, 240, int64(1024)))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/posts/p1/comments?limit=10", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", res.Code, res.Body.String())
	}

	var payload struct {
		Items []commentResponse `json:"items"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &payload); err != nil {
		t.Fatalf("unmarshal error: %v", err)
	}
	if len(payload.Items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(payload.Items))
	}

	imgComment := payload.Items[0]
	if len(imgComment.Media) != 1 || imgComment.Media[0].ID != "m1" {
		t.Fatalf("expected image comment to have media m1, got %+v", imgComment.Media)
	}
	if len(imgComment.Attachments) != 1 || imgComment.Attachments[0].Type != "image" || imgComment.Attachments[0].ID != "m1" {
		t.Fatalf("expected image attachment, got %+v", imgComment.Attachments)
	}

	stkComment := payload.Items[1]
	if stkComment.StickerID == nil || *stkComment.StickerID != "mf_01" {
		t.Fatalf("expected sticker_id mf_01, got %v", stkComment.StickerID)
	}
	if len(stkComment.Attachments) != 1 || stkComment.Attachments[0].Type != "sticker" || stkComment.Attachments[0].StickerID != "mf_01" {
		t.Fatalf("expected sticker attachment, got %+v", stkComment.Attachments)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}



