package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestRecordPostViewDoesNotRequireBearerToken(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`
		SELECT view_count
		FROM posts
		WHERE id = $1
		  AND publication_status = 'published'
		  AND moderation_status = 'normal'
		  AND type <> 'market'
		  AND deleted_at IS NULL
		FOR UPDATE`)).
		WithArgs("p1").
		WillReturnRows(sqlmock.NewRows([]string{"view_count"}).AddRow(int64(7)))
	mock.ExpectExec(regexp.QuoteMeta(`
		INSERT INTO post_view_events (post_id, viewer_key, view_date)
		VALUES ($1, $2, $3)
		ON CONFLICT (post_id, viewer_key, view_date) DO NOTHING`)).
		WithArgs("p1", sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery(regexp.QuoteMeta(`
			UPDATE posts
			SET view_count = view_count + 1, updated_at = now()
			WHERE id = $1
			RETURNING view_count`)).
		WithArgs("p1").
		WillReturnRows(sqlmock.NewRows([]string{"view_count"}).AddRow(int64(8)))
	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodPost, "/api/v1/posts/p1/view", nil)
	res := httptest.NewRecorder()
	NewHandler(db).ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("record view status=%d body=%s", res.Code, res.Body.String())
	}
	if cookie := res.Result().Cookies(); len(cookie) == 0 || cookie[0].Name != postViewVisitorCookie {
		t.Fatalf("anonymous view should set visitor cookie, got %+v", cookie)
	}
	if !strings.Contains(res.Body.String(), `"recorded":true`) || !strings.Contains(res.Body.String(), `"view_count":8`) {
		t.Fatalf("unexpected body: %s", res.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestRecordPostViewDedupesAgainstPostgres(t *testing.T) {
	s := feedIntegrationServer(t)
	_, ids := insertFeedFixtures(t, s)
	postID := ids["p1"]
	handler := NewHandler(s.db)

	record := func(cookie *http.Cookie, token string) (*httptest.ResponseRecorder, map[string]any) {
		t.Helper()
		req := httptest.NewRequest(http.MethodPost, "/api/v1/posts/"+postID+"/view", nil)
		if cookie != nil {
			req.AddCookie(cookie)
		}
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		res := httptest.NewRecorder()
		handler.ServeHTTP(res, req)
		if res.Code != http.StatusOK {
			t.Fatalf("record view status=%d body=%s", res.Code, res.Body.String())
		}
		var payload map[string]any
		if err := json.Unmarshal(res.Body.Bytes(), &payload); err != nil {
			t.Fatal(err)
		}
		return res, payload
	}

	res1, payload1 := record(nil, "")
	if payload1["recorded"] != true {
		t.Fatalf("first anonymous view should record: %+v", payload1)
	}
	cookies := res1.Result().Cookies()
	if len(cookies) != 1 || cookies[0].Name != postViewVisitorCookie {
		t.Fatalf("visitor cookie = %+v", cookies)
	}
	_, payload2 := record(cookies[0], "")
	if payload2["recorded"] != false {
		t.Fatalf("same anonymous visitor should be deduped: %+v", payload2)
	}
	_, payload3 := record(nil, "")
	if payload3["recorded"] != true {
		t.Fatalf("different anonymous visitor should record: %+v", payload3)
	}

	suffix := time.Now().UnixNano()
	session, err := auth.NewService(s.db).Register(context.Background(), auth.RegisterInput{
		Username: "view_user_" + strings.ReplaceAll(time.Unix(0, suffix).Format("150405.000000000"), ".", "_"),
		Password: "安全密码12345",
		Nickname: "浏览测试",
	}, auth.SessionMetadata{UserAgent: "post-view-test", IPAddress: "127.0.0.1"})
	if err != nil {
		t.Fatal(err)
	}
	_, payload4 := record(nil, session.AccessToken)
	if payload4["recorded"] != true {
		t.Fatalf("first authenticated view should record: %+v", payload4)
	}
	_, payload5 := record(nil, session.AccessToken)
	if payload5["recorded"] != false {
		t.Fatalf("same authenticated user should be deduped: %+v", payload5)
	}

	var viewCount, histories int
	if err := s.db.QueryRow(`SELECT view_count FROM posts WHERE id = $1`, postID).Scan(&viewCount); err != nil {
		t.Fatal(err)
	}
	if viewCount != 3 {
		t.Fatalf("view_count=%d, want 3", viewCount)
	}
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM user_post_histories WHERE user_id = $1 AND post_id = $2`, session.User.ID, postID).Scan(&histories); err != nil {
		t.Fatal(err)
	}
	if histories != 0 {
		t.Fatalf("/view should not write user_post_histories, got %d", histories)
	}
}
