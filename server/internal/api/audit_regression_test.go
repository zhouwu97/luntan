package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zhouwu97/luntan/server/internal/auth"
)

func TestMediaPublicVisibilityRequiresNormalModeration(t *testing.T) {
	for _, condition := range []string{
		"p.moderation_status = 'normal'",
		"c.moderation_status = 'normal'",
	} {
		if !strings.Contains(mediaPublicVisibilityExpr, condition) {
			t.Fatalf("media public visibility must require %s; expression=%s", condition, mediaPublicVisibilityExpr)
		}
	}
}

func TestMediaInUseCoversProfileCommunityAndActivityReferences(t *testing.T) {
	for _, reference := range []string{
		"user_profiles up",
		"up.avatar_media_id = ma.id",
		"up.background_media_id = ma.id",
		"communities c",
		"c.avatar_media_id = ma.id",
		"c.banner_media_id = ma.id",
		"activities a",
		"a.cover_media_id = ma.id",
	} {
		if !strings.Contains(mediaInUseExpr, reference) {
			t.Fatalf("media in-use expression must cover %s; expression=%s", reference, mediaInUseExpr)
		}
	}
}

func TestMediaResponsesDoNotExposeInternalObjectKey(t *testing.T) {
	response := mediaResponse(mediaAsset{ID: "media-1", ObjectKey: "media/user-1/media-1"})
	if _, exposed := response["object_key"]; exposed {
		t.Fatal("media API responses must not expose internal object keys")
	}
}

func TestPostTypeTransitionKeepsBusinessStateConsistent(t *testing.T) {
	cases := []struct {
		name        string
		current     string
		next        string
		canModerate bool
		wantErr     error
	}{
		{name: "ordinary user cannot promote post to activity", current: "normal", next: "activity", wantErr: ErrPermissionDenied},
		{name: "activity posts use activity entity API", current: "normal", next: "activity", canModerate: true, wantErr: ErrActivityManagedSeparately},
		{name: "normal to poll is allowed for a complete poll payload", current: "normal", next: "poll"},
		{name: "poll remains poll", current: "poll", next: "poll"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validatePostTypeTransition(tc.current, tc.next, tc.canModerate)
			if tc.wantErr == nil {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			if err != tc.wantErr {
				t.Fatalf("error=%v, want %v", err, tc.wantErr)
			}
		})
	}
}

func TestUpdatePostRejectsActivityPromotionForOrdinaryUser(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	createdAt := time.Date(2026, 8, 31, 0, 0, 0, 0, time.UTC)
	mock.ExpectBegin()
	mock.ExpectQuery(`(?s)SELECT id, author_id, community_id, type, title, content.*FROM posts WHERE id = \$1 FOR UPDATE`).
		WithArgs("post-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "author_id", "community_id", "type", "title", "content",
			"publication_status", "moderation_status", "created_at", "updated_at", "published_at", "deleted_at",
		}).AddRow("post-1", "user-1", "community-1", "normal", "原标题", "原正文", "published", "normal", createdAt, createdAt, createdAt, nil))
	mock.ExpectQuery(`(?s)SELECT EXISTS \(.*FROM user_roles ur.*`).
		WithArgs("user-1", "moderation.action").
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	req := httptest.NewRequest(http.MethodPut, "/api/v1/posts/post-1", strings.NewReader(`{"community_id":"community-1","type":"activity","title":"新标题","content":"新正文"}`))
	req = req.WithContext(context.WithValue(req.Context(), authenticatedUserContextKey{}, auth.User{ID: "user-1", AccountType: "email"}))
	rec := httptest.NewRecorder()
	(&Server{db: db}).updatePost(rec, req, "post-1")

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status=%d body=%s, want 403", rec.Code, rec.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unexpected post mutation: %v", err)
	}
}

func TestDeletePollTxRemovesVotesOptionsAndPoll(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectBegin()
	mock.ExpectExec(`(?s)DELETE FROM poll_votes.*SELECT id FROM polls WHERE post_id = \$1`).
		WithArgs("post-poll").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`(?s)DELETE FROM poll_options.*SELECT id FROM polls WHERE post_id = \$1`).
		WithArgs("post-poll").WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectExec(`DELETE FROM polls WHERE post_id = \$1`).
		WithArgs("post-poll").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := deletePollTx(context.Background(), tx, "post-poll"); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("poll cleanup expectations: %v", err)
	}
}
