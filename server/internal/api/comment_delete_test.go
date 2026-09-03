package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestRegularUserCanDeleteOwnComment(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("user-author", "user", "active", "普通作者", 1, 0, "email", "", false, nil, false))

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id, deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-1").
		WillReturnRows(sqlmock.NewRows([]string{"author_id", "deleted_at"}).AddRow("user-author", nil))

	// softDeleteCommentTx
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id, COALESCE(root_id, id), deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-1").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "deleted_at"}).AddRow("post-1", "comment-1", nil))

	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comments SET deleted_at = now(), publication_status = 'deleted', deleted_by = NULLIF($2, ''), delete_reason = $3, moderation_case_id = NULLIF($4, ''), updated_at = now() WHERE id = $1 AND deleted_at IS NULL`)).
		WithArgs("comment-1", "user-author", "用户主动删除评论", "").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// decrement post comment count
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0), updated_at = now() WHERE id = $1`)).
		WithArgs("post-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/comment-1", nil)
	req.Header.Set("Authorization", "Bearer user-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestRegularUserCannotDeleteAnotherUsersComment(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("other-user", "other", "active", "普通用户", 1, 0, "email", "", false, nil, false))

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id, deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-1").
		WillReturnRows(sqlmock.NewRows([]string{"author_id", "deleted_at"}).AddRow("author-1", nil))

	// canModerate check -> false
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("other-user", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	mock.ExpectRollback()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/comment-1", nil)
	req.Header.Set("Authorization", "Bearer other-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestAdminCanDeleteOwnComment(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("admin-1", "admin", "active", "管理员", 1, 0, "email", "", false, nil, false))

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id, deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-own").
		WillReturnRows(sqlmock.NewRows([]string{"author_id", "deleted_at"}).AddRow("admin-1", nil))

	// softDeleteCommentTx: admin deleting own comment -> isAuthor is true
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id, COALESCE(root_id, id), deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-own").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "deleted_at"}).AddRow("post-1", "comment-own", nil))

	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comments SET deleted_at = now(), publication_status = 'deleted', deleted_by = NULLIF($2, ''), delete_reason = $3, moderation_case_id = NULLIF($4, ''), updated_at = now() WHERE id = $1 AND deleted_at IS NULL`)).
		WithArgs("comment-own", "admin-1", "用户主动删除评论", "").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// decrement post comment count
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0), updated_at = now() WHERE id = $1`)).
		WithArgs("post-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/comment-own", nil)
	req.Header.Set("Authorization", "Bearer admin-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestAdminCanDeleteAnotherUsersComment(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("admin-1", "admin", "active", "管理员", 1, 0, "email", "", false, nil, false))

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id, deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-other").
		WillReturnRows(sqlmock.NewRows([]string{"author_id", "deleted_at"}).AddRow("author-2", nil))

	// canModerate check -> true
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*JOIN role_permissions rp.*`).
		WithArgs("admin-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))

	// softDeleteCommentTx
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id, COALESCE(root_id, id), deleted_at FROM comments WHERE id = $1 FOR UPDATE`)).
		WithArgs("comment-other").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "deleted_at"}).AddRow("post-1", "comment-root", nil))

	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comments SET deleted_at = now(), publication_status = 'deleted', deleted_by = NULLIF($2, ''), delete_reason = $3, moderation_case_id = NULLIF($4, ''), updated_at = now() WHERE id = $1 AND deleted_at IS NULL`)).
		WithArgs("comment-other", "admin-1", "管理员手动删除评论", "").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// root_id != comment_id, decrement reply_count on root comment
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comments SET reply_count = GREATEST(reply_count - 1, 0), updated_at = now() WHERE id = $1`)).
		WithArgs("comment-root").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// decrement post comment count
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0), updated_at = now() WHERE id = $1`)).
		WithArgs("post-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/comment-other", nil)
	req.Header.Set("Authorization", "Bearer admin-token")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestUnauthenticatedUserCannotDeleteComment(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	req := httptest.NewRequest(http.MethodDelete, "/api/v1/comments/c-1", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", res.Code)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestCreateCommentRejectsOverNineMedia(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("user-1", "user1", "active", "用户1", 1, 0, "email", "", false, nil, false))

	mock.ExpectQuery(`(?s)SELECT ends_at FROM restrictions WHERE user_id = \$1 AND restriction_type = 'mute'`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"ends_at"}))

	// 10 media IDs exceeds maximum of 9
	body := `{"content": "多图评论测试", "media_ids": ["m1","m2","m3","m4","m5","m6","m7","m8","m9","m10"]}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts/post-1/comments", bytes.NewBufferString(body))
	req.Header.Set("Authorization", "Bearer user-token")
	req.Header.Set("Content-Type", "application/json")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestCreateCommentAndReplyMultiImageSuccess(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	// 1. Session check
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("user-1", "user1", "active", "用户1", 1, 0, "email", "", false, nil, false))

	// 2. Mute check
	mock.ExpectQuery(`(?s)SELECT ends_at FROM restrictions WHERE user_id = \$1 AND restriction_type = 'mute'`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"ends_at"}))

	// 3. Media assets validation for 3 images (all ready, image/*, owned by user-1)
	mediaIDs := []string{"m1", "m2", "m3"}
	for _, mid := range mediaIDs {
		mock.ExpectQuery(regexp.QuoteMeta(`SELECT owner_id, status, mime_type FROM media_assets WHERE id = $1 AND deleted_at IS NULL`)).
			WithArgs(mid).
			WillReturnRows(sqlmock.NewRows([]string{"owner_id", "status", "mime_type"}).AddRow("user-1", "ready", "image/jpeg"))
	}

	// 4. Block check against post author
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id FROM posts WHERE id = $1 AND deleted_at IS NULL`)).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{"author_id"}).AddRow("author-99"))

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1))`)).
		WithArgs("user-1", "author-99").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	// 5. Transaction start
	mock.ExpectBegin()

	// 6. Idempotency atomic lock insertion
	mock.ExpectQuery(`(?s)INSERT INTO comment_idempotency_keys.*ON CONFLICT.*RETURNING comment_id`).
		WithArgs("user-1", "idem-key-123", sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"comment_id"}).AddRow("comment-100"))

	// 7. Post existence check
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL FOR UPDATE`)).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("post-1"))

	// 8. Idempotency key update
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comment_idempotency_keys SET comment_id = $1 WHERE user_id = $2 AND idempotency_key = $3`)).
		WithArgs(sqlmock.AnyArg(), "user-1", "idem-key-123").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 9. Comments row insertion
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO comments (id, post_id, author_id, root_id, parent_id, reply_to_user_id, content, sticker_id, publication_status, moderation_status, created_at, updated_at, published_at)`)).
		WithArgs(sqlmock.AnyArg(), "post-1", "user-1", sqlmock.AnyArg(), "", "", "3张图根评论", "", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 10. EXACT 3 rows in comment_media with sort_order = 0, 1, 2
	for idx, mid := range mediaIDs {
		mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO comment_media (comment_id, media_id, sort_order, created_at) VALUES ($1, $2, $3, $4)`)).
			WithArgs(sqlmock.AnyArg(), mid, idx, sqlmock.AnyArg()).
			WillReturnResult(sqlmock.NewResult(1, 1))
	}

	// 11. Post comment_count increment
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE posts SET comment_count = comment_count + 1, updated_at = $1 WHERE id = $2`)).
		WithArgs(sqlmock.AnyArg(), "post-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 12. Exp reward
	mock.ExpectQuery(`(?s)SELECT COALESCE\(up\.experience, 0\).*FROM users u`).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"experience", "account_type"}).AddRow(0, "email"))
	mock.ExpectQuery(`(?s)SELECT experience_after.*FROM experience_transactions`).
		WithArgs("user-1", sqlmock.AnyArg()).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`(?s)SELECT count\(\*\).*FROM experience_transactions`).
		WithArgs("user-1", "comment").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))
	mock.ExpectExec(`(?s)UPDATE user_profiles.*SET experience = \$1, level = \$2`).
		WithArgs(int64(5), 1, "user-1").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`(?s)INSERT INTO experience_transactions`).
		WithArgs(sqlmock.AnyArg(), "user-1", "comment", int64(5), int64(5), "参与回复", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 13. Points reward
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(0))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("user-1", sqlmock.AnyArg()).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COALESCE(SUM(delta), 0) FROM point_transactions WHERE user_id = $1 AND delta > 0 AND source IN ('post', 'like', 'comment') AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`)).
		WithArgs("user-1").
		WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(0))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(2), "user-1").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "user-1", "comment", int64(2), int64(2), "发表评论", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 13. loadCommentResponseTx
	mock.ExpectQuery(`(?s)SELECT c\.id, c\.post_id, c\.author_id.*FROM comments c.*WHERE c\.id = \$1`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "post_id", "author_id", "username", "nickname", "level",
			"avatar_id", "avatar_key", "root_id", "parent_id", "reply_to_user_id",
			"content", "sticker_id", "like_count", "dislike_count", "reply_count",
			"publication_status", "moderation_status", "created_at", "updated_at",
			"floor_no",
		}).AddRow(
			"comment-100", "post-1", "user-1", "user1", "用户1", 1,
			"", "", "comment-100", "", "",
			"3张图根评论", "", 0, 0, 0,
			"published", "normal", time.Now(), time.Now(), 1,
		))

	// Batch media load (enrichCommentsMedia) returns 3 rows ordered by sort_order
	mock.ExpectQuery(`(?s)SELECT cm\.comment_id, ma\.id, ma\.mime_type, ma\.width, ma\.height, ma\.original_name, ma\.object_key.*FROM comment_media cm.*JOIN media_assets ma.*WHERE cm\.comment_id IN \(\$1\)`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"comment_id", "id", "mime_type", "width", "height", "original_name", "object_key",
		}).
			AddRow("comment-100", "m1", "image/jpeg", 1000, 800, "1.jpg", "media/1.jpg").
			AddRow("comment-100", "m2", "image/jpeg", 1200, 900, "2.jpg", "media/2.jpg").
			AddRow("comment-100", "m3", "image/jpeg", 800, 1600, "3.jpg", "media/3.jpg"))

	// viewer reactions query
	mock.ExpectQuery(`(?s)SELECT\s+EXISTS \(SELECT 1 FROM comment_reactions cr WHERE cr\.comment_id = c\.id AND cr\.user_id = \$2 AND cr\.reaction_type = 'like'\),\s+EXISTS \(SELECT 1 FROM comment_reactions cr WHERE cr\.comment_id = c\.id AND cr\.user_id = \$2 AND cr\.reaction_type = 'dislike'\)\s+FROM comments c WHERE c\.id = \$1`).
		WithArgs(sqlmock.AnyArg(), "user-1").
		WillReturnRows(sqlmock.NewRows([]string{"has_liked", "has_disliked"}).AddRow(false, false))

	// Transaction commit
	mock.ExpectCommit()

	body := `{"content": "3张图根评论", "media_ids": ["m1","m2","m3"]}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts/post-1/comments", bytes.NewBufferString(body))
	req.Header.Set("Authorization", "Bearer user-token")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Idempotency-Key", "idem-key-123")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}

	var resp struct {
		ID    string `json:"id"`
		Media []struct {
			ID   string `json:"id"`
			Type string `json:"type"`
		} `json:"media"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal response failed: %v", err)
	}
	if len(resp.Media) != 3 {
		t.Fatalf("expected 3 media items returned in comment response, got %d", len(resp.Media))
	}
	if resp.Media[0].ID != "m1" || resp.Media[1].ID != "m2" || resp.Media[2].ID != "m3" {
		t.Fatalf("unexpected media order: %+v", resp.Media)
	}
}

func TestCreateReplyMultiImageSuccess(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	// 1. Session check
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username.*FROM sessions s`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "username", "status", "nickname", "level", "experience", "account_type",
			"email", "email_verified", "email_verified_at", "has_password",
		}).AddRow("user-2", "user2", "active", "用户2", 1, 0, "email", "", false, nil, false))

	// 2. Mute check
	mock.ExpectQuery(`(?s)SELECT ends_at FROM restrictions WHERE user_id = \$1 AND restriction_type = 'mute'`).
		WithArgs("user-2").
		WillReturnRows(sqlmock.NewRows([]string{"ends_at"}))

	// 3. Media assets validation for 3 images
	mediaIDs := []string{"m1", "m2", "m3"}
	for _, mid := range mediaIDs {
		mock.ExpectQuery(regexp.QuoteMeta(`SELECT owner_id, status, mime_type FROM media_assets WHERE id = $1 AND deleted_at IS NULL`)).
			WithArgs(mid).
			WillReturnRows(sqlmock.NewRows([]string{"owner_id", "status", "mime_type"}).AddRow("user-2", "ready", "image/png"))
	}

	// 4. Block check against parent comment author
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT author_id FROM comments WHERE id = $1 AND deleted_at IS NULL`)).
		WithArgs("root-comment-1").
		WillReturnRows(sqlmock.NewRows([]string{"author_id"}).AddRow("root-author-1"))

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT EXISTS (SELECT 1 FROM blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1))`)).
		WithArgs("user-2", "root-author-1").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	// 5. Transaction start
	mock.ExpectBegin()

	// 6. Idempotency atomic lock
	mock.ExpectQuery(`(?s)INSERT INTO comment_idempotency_keys.*ON CONFLICT.*RETURNING comment_id`).
		WithArgs("user-2", "reply-key-123", sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"comment_id"}).AddRow("reply-200"))

	// 7. Post existence check
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM posts WHERE id = $1 AND publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL FOR UPDATE`)).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("post-1"))

	// 8. Parent comment lookup
	mock.ExpectQuery(`(?s)SELECT post_id, COALESCE\(root_id, id\), author_id FROM comments WHERE id = \$1 AND deleted_at IS NULL AND publication_status = 'published' AND moderation_status = 'normal'`).
		WithArgs("root-comment-1").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "author_id"}).AddRow("post-1", "root-comment-1", "root-author-1"))

	// 9. Idempotency key update
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comment_idempotency_keys SET comment_id = $1 WHERE user_id = $2 AND idempotency_key = $3`)).
		WithArgs(sqlmock.AnyArg(), "user-2", "reply-key-123").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 10. Comments row insertion for reply
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO comments (id, post_id, author_id, root_id, parent_id, reply_to_user_id, content, sticker_id, publication_status, moderation_status, created_at, updated_at, published_at)`)).
		WithArgs(sqlmock.AnyArg(), "post-1", "user-2", "root-comment-1", "root-comment-1", "root-author-1", "3张图楼中楼回复", "", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 11. EXACT 3 rows in comment_media with sort_order = 0, 1, 2
	for idx, mid := range mediaIDs {
		mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO comment_media (comment_id, media_id, sort_order, created_at) VALUES ($1, $2, $3, $4)`)).
			WithArgs(sqlmock.AnyArg(), mid, idx, sqlmock.AnyArg()).
			WillReturnResult(sqlmock.NewResult(1, 1))
	}

	// 12. Root comment reply_count increment
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE comments SET reply_count = reply_count + 1, updated_at = $1 WHERE id = $2`)).
		WithArgs(sqlmock.AnyArg(), "root-comment-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 13. Post comment_count increment
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE posts SET comment_count = comment_count + 1, updated_at = $1 WHERE id = $2`)).
		WithArgs(sqlmock.AnyArg(), "post-1").
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 14. Reply notification enqueue (writes notifications then outbox_events)
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO notifications (id, user_id, type, actor_id, target_type, target_id, target_data, is_read, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, false, $8)`)).
		WithArgs(sqlmock.AnyArg(), "root-author-1", "reply", "user-2", "post", "post-1", sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO outbox_events (id, event_type, aggregate_type, aggregate_id, payload, status, available_at, created_at) VALUES ($1, $2, $3, $4, $5::jsonb, 'pending', $6, $6)`)).
		WithArgs(sqlmock.AnyArg(), "notification.created", "notification", sqlmock.AnyArg(), sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 15. Exp reward
	mock.ExpectQuery(`(?s)SELECT COALESCE\(up\.experience, 0\).*FROM users u`).
		WithArgs("user-2").
		WillReturnRows(sqlmock.NewRows([]string{"experience", "account_type"}).AddRow(0, "email"))
	mock.ExpectQuery(`(?s)SELECT experience_after.*FROM experience_transactions`).
		WithArgs("user-2", sqlmock.AnyArg()).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`(?s)SELECT count\(\*\).*FROM experience_transactions`).
		WithArgs("user-2", "comment").
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(0))
	mock.ExpectExec(`(?s)UPDATE user_profiles.*SET experience = \$1, level = \$2`).
		WithArgs(int64(5), 1, "user-2").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`(?s)INSERT INTO experience_transactions`).
		WithArgs(sqlmock.AnyArg(), "user-2", "comment", int64(5), int64(5), "参与回复", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 16. Points reward
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("user-2").
		WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(0))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("user-2", sqlmock.AnyArg()).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COALESCE(SUM(delta), 0) FROM point_transactions WHERE user_id = $1 AND delta > 0 AND source IN ('post', 'like', 'comment') AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`)).
		WithArgs("user-2").
		WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(0))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(2), "user-2").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "user-2", "comment", int64(2), int64(2), "发表评论", sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// 17. loadCommentResponseTx
	mock.ExpectQuery(`(?s)SELECT c\.id, c\.post_id, c\.author_id.*FROM comments c.*WHERE c\.id = \$1`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "post_id", "author_id", "username", "nickname", "level",
			"avatar_id", "avatar_key", "root_id", "parent_id", "reply_to_user_id",
			"content", "sticker_id", "like_count", "dislike_count", "reply_count",
			"publication_status", "moderation_status", "created_at", "updated_at",
			"floor_no",
		}).AddRow(
			"reply-200", "post-1", "user-2", "user2", "用户2", 1,
			"", "", "root-comment-1", "root-comment-1", "root-author-1",
			"3张图楼中楼回复", "", 0, 0, 0,
			"published", "normal", time.Now(), time.Now(), nil,
		))

	// enrichReplyToUser query
	mock.ExpectQuery(`(?s)SELECT u\.id, u\.username, COALESCE\(up\.nickname, u\.username\), COALESCE\(up\.level, 1\), COALESCE\(up\.avatar_media_id, ''\), COALESCE\(ma\.object_key, ''\) FROM users u LEFT JOIN user_profiles up ON up\.user_id = u\.id LEFT JOIN media_assets ma ON ma\.id = up\.avatar_media_id WHERE u\.id = \$1 AND u\.deleted_at IS NULL`).
		WithArgs("root-author-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "username", "nickname", "level", "avatar_media_id", "avatar_key"}).AddRow("root-author-1", "root1", "根作者", 1, "", ""))

	// Batch media load (enrichCommentsMedia) returns 3 rows ordered by sort_order
	mock.ExpectQuery(`(?s)SELECT cm\.comment_id, ma\.id, ma\.mime_type, ma\.width, ma\.height, ma\.original_name, ma\.object_key.*FROM comment_media cm.*JOIN media_assets ma.*WHERE cm\.comment_id IN \(\$1\)`).
		WithArgs(sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{
			"comment_id", "id", "mime_type", "width", "height", "original_name", "object_key",
		}).
			AddRow("reply-200", "m1", "image/png", 800, 600, "1.png", "media/1.png").
			AddRow("reply-200", "m2", "image/png", 1000, 750, "2.png", "media/2.png").
			AddRow("reply-200", "m3", "image/png", 600, 1200, "3.png", "media/3.png"))

	// viewer reactions query
	mock.ExpectQuery(`(?s)SELECT\s+EXISTS \(SELECT 1 FROM comment_reactions cr WHERE cr\.comment_id = c\.id AND cr\.user_id = \$2 AND cr\.reaction_type = 'like'\),\s+EXISTS \(SELECT 1 FROM comment_reactions cr WHERE cr\.comment_id = c\.id AND cr\.user_id = \$2 AND cr\.reaction_type = 'dislike'\)\s+FROM comments c WHERE c\.id = \$1`).
		WithArgs(sqlmock.AnyArg(), "user-2").
		WillReturnRows(sqlmock.NewRows([]string{"has_liked", "has_disliked"}).AddRow(false, false))

	// Transaction commit
	mock.ExpectCommit()

	body := `{"content": "3张图楼中楼回复", "parent_id": "root-comment-1", "media_ids": ["m1","m2","m3"]}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts/post-1/comments", bytes.NewBufferString(body))
	req.Header.Set("Authorization", "Bearer user-token")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Idempotency-Key", "reply-key-123")
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created, got %d (body: %s)", res.Code, res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}

	var resp struct {
		ID       string `json:"id"`
		ParentID string `json:"parent_id"`
		Media    []struct {
			ID   string `json:"id"`
			Type string `json:"type"`
		} `json:"media"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal response failed: %v", err)
	}
	if len(resp.Media) != 3 {
		t.Fatalf("expected 3 media items returned in reply response, got %d", len(resp.Media))
	}
	if resp.Media[0].ID != "m1" || resp.Media[1].ID != "m2" || resp.Media[2].ID != "m3" {
		t.Fatalf("unexpected media order: %+v", resp.Media)
	}
	if resp.ParentID != "root-comment-1" {
		t.Fatalf("expected parent_id root-comment-1, got %s", resp.ParentID)
	}
}
