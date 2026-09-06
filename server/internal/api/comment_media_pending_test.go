package api

import (
	"context"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestCommentImageBeforeWorkerUsesStableGatewayURL(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	mock.ExpectQuery("SELECT cm.comment_id, ma.id").WithArgs("comment-new").WillReturnRows(sqlmock.NewRows([]string{"comment_id", "id", "mime_type", "width", "height", "original_name", "object_key"}).AddRow("comment-new", "media_abcd", "image/jpeg", 200, 200, "test.jpg", "media/owner/media_abcd"))
	mock.ExpectQuery("SELECT mv.media_id, mv.variant").WithArgs("media_abcd").WillReturnRows(sqlmock.NewRows([]string{"media_id", "variant", "object_key", "mime_type", "width", "height", "size_bytes"}))
	items := []commentResponse{{ID: "comment-new"}}
	if err := enrichCommentsMedia(context.Background(), db, items); err != nil {
		t.Fatal(err)
	}
	if len(items[0].Media) != 1 || items[0].Media[0].URL != "/api/v1/media-file/media_abcd/detail" {
		t.Fatalf("异步处理前不应下发源地址: %+v", items[0].Media)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
