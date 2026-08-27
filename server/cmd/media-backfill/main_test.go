package main

import (
	"context"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestRunBackfillDryRunAndExecution(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	ctx := context.Background()

	// 1. Dry Run 测试
	mock.ExpectQuery(`SELECT ma\.id, ma\.object_key, ma\.mime_type, ma\.width, ma\.height, ma\.size, ma\.sha256 FROM media_assets ma WHERE ma\.status = 'ready'`).
		WillReturnRows(sqlmock.NewRows([]string{"id", "object_key", "mime_type", "width", "height", "size", "sha256"}).
			AddRow("m1", "media/u1/m1", "image/jpeg", 1920, 1080, 500000, "hash1").
			AddRow("m2", "media/u2/m2", "image/png", 800, 600, 200000, "hash2"))

	count, err := RunBackfill(ctx, db, 50, 0, true)
	if err != nil {
		t.Fatalf("dry run failed: %v", err)
	}
	if count != 2 {
		t.Fatalf("expected 2 legacy media scanned, got %d", count)
	}

	// 2. 真实 Backfill 写入 Outbox 事件
	mock.ExpectQuery(`SELECT ma\.id, ma\.object_key, ma\.mime_type, ma\.width, ma\.height, ma\.size, ma\.sha256 FROM media_assets ma WHERE ma\.status = 'ready'`).
		WillReturnRows(sqlmock.NewRows([]string{"id", "object_key", "mime_type", "width", "height", "size", "sha256"}).
			AddRow("m1", "media/u1/m1", "image/jpeg", 1920, 1080, 500000, "hash1"))

	mock.ExpectBegin()
	mock.ExpectExec(`INSERT INTO outbox_events`).
		WithArgs(sqlmock.AnyArg(), "m1", sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	enqueued, err := RunBackfill(ctx, db, 50, 0, false)
	if err != nil {
		t.Fatalf("actual backfill failed: %v", err)
	}
	if enqueued != 1 {
		t.Fatalf("expected 1 enqueued event, got %d", enqueued)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet sqlmock expectations: %v", err)
	}
}
