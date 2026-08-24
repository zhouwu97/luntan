package api

import (
	"database/sql"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestAwardPointsTxIsIdempotentByEventKey(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(100))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "post:create:p1").WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(110), "u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "u1", "post", int64(10), int64(110), "发布帖子", "post:create:p1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := awardPointsTx(t.Context(), tx, "u1", "post", "发布帖子", "post:create:p1", 10); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(110))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "post:create:p1").WillReturnRows(sqlmock.NewRows([]string{"balance_after"}).AddRow(110))
	mock.ExpectCommit()
	tx, err = db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := awardPointsTx(t.Context(), tx, "u1", "post", "发布帖子", "post:create:p1", 10); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
