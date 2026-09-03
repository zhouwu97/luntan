package api

import (
	"context"
	"database/sql"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

// TestLikeConcurrentRaceCondition 验证点赞并发时不会超发
// 场景：已有 4 次点赞积分，两个并发点赞同时到达
// 预期：只有一个能获得第 5 次积分，另一个被拒绝
func TestLikeConcurrentRaceCondition(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// 第一个并发请求：成功获得第 5 次积分
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(4))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "like:post:p5:user:u1").WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COUNT(*) FROM point_transactions WHERE user_id = $1 AND source = 'like' AND delta > 0 AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(4))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COALESCE(SUM(delta), 0) FROM point_transactions WHERE user_id = $1 AND delta > 0 AND source IN ('post', 'like', 'comment') AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(4))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(5), "u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "u1", "like", int64(1), int64(5), "点赞", "like:post:p5:user:u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	tx, _ := db.Begin()
	if err := awardLikePointTx(context.Background(), tx, "u1", "post", "p5", 1, 5, 20); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	// 第二个并发请求：因为用户行锁，会看到已有 5 次点赞，被拒绝
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(5))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "like:post:p6:user:u1").WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COUNT(*) FROM point_transactions WHERE user_id = $1 AND source = 'like' AND delta > 0 AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(5))
	mock.ExpectCommit()

	tx, _ = db.Begin()
	if err := awardLikePointTx(context.Background(), tx, "u1", "post", "p6", 1, 5, 20); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestGlobalDailyLimitRaceCondition 验证全局每日上限的并发安全性
// 场景：当日已有 19 积分，两个操作（发帖 10 分 + 评论 2 分）并发
// 预期：发帖只能获得 1 分，评论 0 分，总计不超过 20 分
func TestGlobalDailyLimitRaceCondition(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// 发帖请求：当日已 19 分，发帖 10 分被截断为 1 分
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(19))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "post:create:p1").WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COALESCE(SUM(delta), 0) FROM point_transactions WHERE user_id = $1 AND delta > 0 AND source IN ('post', 'like', 'comment') AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(19))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(20), "u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "u1", "post", int64(1), int64(20), "发布帖子", "post:create:p1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	tx, _ := db.Begin()
	if err := awardPointsTx(context.Background(), tx, "u1", "post", "发布帖子", "post:create:p1", 10, 20); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	// 评论请求：因为用户行锁，会看到已达 20 分，不再发放
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(20))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "comment:create:c1").WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COALESCE(SUM(delta), 0) FROM point_transactions WHERE user_id = $1 AND delta > 0 AND source IN ('post', 'like', 'comment') AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(20))
	mock.ExpectCommit()

	tx, _ = db.Begin()
	if err := awardPointsTx(context.Background(), tx, "u1", "comment", "发表评论", "comment:create:c1", 2, 20); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
