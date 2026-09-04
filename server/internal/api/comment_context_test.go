package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestGetCommentContextRootComment(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	// 1. Query comment metadata
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id, root_id, parent_id, publication_status, moderation_status, deleted_at FROM comments WHERE id = $1`)).
		WithArgs("comm-root-1").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "parent_id", "publication_status", "moderation_status", "deleted_at"}).
			AddRow("post-100", "comm-root-1", nil, "published", "normal", nil))

	// 2. loadCommentResponse for root comment
	mock.ExpectQuery(`(?s)SELECT c\.id, c\.post_id, c\.author_id, u\.username.*FROM comments c.*WHERE c\.id = \$1`).
		WithArgs("comm-root-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "post_id", "author_id", "username", "nickname",
			"level", "avatar_media_id", "avatar_url",
			"root_id", "parent_id", "reply_to_user_id",
			"content", "sticker_id", "like_count", "dislike_count", "reply_count",
			"publication_status", "moderation_status",
			"created_at", "updated_at", "floor_no",
		}).AddRow(
			"comm-root-1", "post-100", "u-1", "user1", "作者一号",
			2, "", "",
			"comm-root-1", "", "",
			"根评论内容", "", 10, 0, 3,
			"published", "normal",
			time.Now(), time.Now(), int64(1),
		))

	// Media enrichment query
	mock.ExpectQuery(`(?s)SELECT cm\.comment_id, ma\.id.*FROM comment_media cm`).
		WithArgs("comm-root-1").
		WillReturnRows(sqlmock.NewRows([]string{"comment_id", "id", "mime_type", "width", "height", "original_name", "object_key"}))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/comments/comm-root-1/context", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body: %s)", res.Code, res.Body.String())
	}

	var payload struct {
		PostID        string `json:"post_id"`
		CommentID     string `json:"comment_id"`
		RootID        string `json:"root_id"`
		IsRoot        bool   `json:"is_root"`
		RootComment   *struct {
			ID      string `json:"id"`
			Content string `json:"content"`
			Floor   *int   `json:"floor"`
		} `json:"root_comment"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &payload); err != nil {
		t.Fatalf("json unmarshal failed: %v", err)
	}

	if payload.PostID != "post-100" || payload.CommentID != "comm-root-1" || payload.RootID != "comm-root-1" || !payload.IsRoot {
		t.Fatalf("unexpected context payload: %+v", payload)
	}
	if payload.RootComment == nil || payload.RootComment.Content != "根评论内容" || payload.RootComment.Floor == nil || *payload.RootComment.Floor != 1 {
		t.Fatalf("unexpected root comment data: %+v", payload.RootComment)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestGetCommentContextNestedReply(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	// 1. Query comment metadata for nested reply
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id, root_id, parent_id, publication_status, moderation_status, deleted_at FROM comments WHERE id = $1`)).
		WithArgs("comm-reply-2").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "parent_id", "publication_status", "moderation_status", "deleted_at"}).
			AddRow("post-100", "comm-root-1", "comm-root-1", "published", "normal", nil))

	// 2. loadCommentResponse for root comment
	mock.ExpectQuery(`(?s)SELECT c\.id, c\.post_id, c\.author_id, u\.username.*FROM comments c.*WHERE c\.id = \$1`).
		WithArgs("comm-root-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "post_id", "author_id", "username", "nickname",
			"level", "avatar_media_id", "avatar_url",
			"root_id", "parent_id", "reply_to_user_id",
			"content", "sticker_id", "like_count", "dislike_count", "reply_count",
			"publication_status", "moderation_status",
			"created_at", "updated_at", "floor_no",
		}).AddRow(
			"comm-root-1", "post-100", "u-1", "user1", "作者一号",
			2, "", "",
			"comm-root-1", "", "",
			"根评论内容", "", 10, 0, 3,
			"published", "normal",
			time.Now(), time.Now(), int64(1),
		))

	mock.ExpectQuery(`(?s)SELECT cm\.comment_id, ma\.id.*FROM comment_media cm`).
		WithArgs("comm-root-1").
		WillReturnRows(sqlmock.NewRows([]string{"comment_id", "id", "mime_type", "width", "height", "original_name", "object_key"}))

	// 3. loadCommentResponse for target comment (reply)
	mock.ExpectQuery(`(?s)SELECT c\.id, c\.post_id, c\.author_id, u\.username.*FROM comments c.*WHERE c\.id = \$1`).
		WithArgs("comm-reply-2").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "post_id", "author_id", "username", "nickname",
			"level", "avatar_media_id", "avatar_url",
			"root_id", "parent_id", "reply_to_user_id",
			"content", "sticker_id", "like_count", "dislike_count", "reply_count",
			"publication_status", "moderation_status",
			"created_at", "updated_at", "floor_no",
		}).AddRow(
			"comm-reply-2", "post-100", "u-2", "user2", "楼中楼用户",
			1, "", "",
			"comm-root-1", "comm-root-1", "",
			"这是楼中楼回复", "", 2, 0, 0,
			"published", "normal",
			time.Now(), time.Now(), nil,
		))

	mock.ExpectQuery(`(?s)SELECT cm\.comment_id, ma\.id.*FROM comment_media cm`).
		WithArgs("comm-reply-2").
		WillReturnRows(sqlmock.NewRows([]string{"comment_id", "id", "mime_type", "width", "height", "original_name", "object_key"}))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/comments/comm-reply-2/context", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body: %s)", res.Code, res.Body.String())
	}

	var payload struct {
		PostID        string `json:"post_id"`
		CommentID     string `json:"comment_id"`
		RootID        string `json:"root_id"`
		ParentID      string `json:"parent_id"`
		IsRoot        bool   `json:"is_root"`
		RootComment   *struct {
			ID string `json:"id"`
		} `json:"root_comment"`
		TargetComment *struct {
			ID      string `json:"id"`
			Content string `json:"content"`
		} `json:"target_comment"`
	}
	if err := json.Unmarshal(res.Body.Bytes(), &payload); err != nil {
		t.Fatalf("json unmarshal failed: %v", err)
	}

	if payload.PostID != "post-100" || payload.CommentID != "comm-reply-2" || payload.RootID != "comm-root-1" || payload.IsRoot {
		t.Fatalf("unexpected context payload: %+v", payload)
	}
	if payload.RootComment == nil || payload.RootComment.ID != "comm-root-1" {
		t.Fatalf("missing or wrong root comment: %+v", payload.RootComment)
	}
	if payload.TargetComment == nil || payload.TargetComment.Content != "这是楼中楼回复" {
		t.Fatalf("missing or wrong target comment: %+v", payload.TargetComment)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}

func TestGetCommentContextNotFoundOrDeleted(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() failed: %v", err)
	}
	defer db.Close()

	// 1. Comment not found
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id, root_id, parent_id, publication_status, moderation_status, deleted_at FROM comments WHERE id = $1`)).
		WithArgs("comm-ghost").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "parent_id", "publication_status", "moderation_status", "deleted_at"}))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/comments/comm-ghost/context", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", res.Code)
	}

	// 2. Comment deleted
	now := time.Now()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT post_id, root_id, parent_id, publication_status, moderation_status, deleted_at FROM comments WHERE id = $1`)).
		WithArgs("comm-deleted").
		WillReturnRows(sqlmock.NewRows([]string{"post_id", "root_id", "parent_id", "publication_status", "moderation_status", "deleted_at"}).
			AddRow("post-100", "comm-deleted", nil, "deleted", "normal", now))

	req = httptest.NewRequest(http.MethodGet, "/api/v1/comments/comm-deleted/context", nil)
	res = httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)

	if res.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for deleted comment, got %d", res.Code)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet SQL expectations: %v", err)
	}
}
