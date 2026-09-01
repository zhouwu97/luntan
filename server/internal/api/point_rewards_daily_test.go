package api

import (
	"context"
	"database/sql"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

// TestDailyPointCompetition 验证点赞和发帖共享每日 +1 额度
func TestDailyPointCompetition(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// 第一次点赞（当天第一个入口）
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT to_char(now() AT TIME ZONE 'Asia/Shanghai', 'YYYY-MM-DD')`)).
		WillReturnRows(sqlmock.NewRows([]string{"to_char"}).AddRow("2026-09-01"))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(0))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "daily:2026-09-01:user:u1").WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(1), "u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "u1", "like", int64(1), int64(1), "点赞帖子", "daily:2026-09-01:user:u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	tx, _ := db.Begin()
	if err := awardDailyPointTx(context.Background(), tx, "u1", "like", "点赞帖子", 1); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	// 第二次点赞（同一天，幂等 key 已存在）
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT to_char(now() AT TIME ZONE 'Asia/Shanghai', 'YYYY-MM-DD')`)).
		WillReturnRows(sqlmock.NewRows([]string{"to_char"}).AddRow("2026-09-01"))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(1))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "daily:2026-09-01:user:u1").WillReturnRows(sqlmock.NewRows([]string{"balance_after"}).AddRow(1))
	mock.ExpectCommit()

	tx, _ = db.Begin()
	if err := awardDailyPointTx(context.Background(), tx, "u1", "like", "点赞帖子", 1); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	// 发帖（同一天，幂等 key 已存在）
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT to_char(now() AT TIME ZONE 'Asia/Shanghai', 'YYYY-MM-DD')`)).
		WillReturnRows(sqlmock.NewRows([]string{"to_char"}).AddRow("2026-09-01"))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(1))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "daily:2026-09-01:user:u1").WillReturnRows(sqlmock.NewRows([]string{"balance_after"}).AddRow(1))
	mock.ExpectCommit()

	tx, _ = db.Begin()
	if err := awardDailyPointTx(context.Background(), tx, "u1", "post", "发布帖子", 1); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestRecommendationBonusIsIdempotentPerPost 验证推荐积分按帖子终身只奖励一次
func TestRecommendationBonusIsIdempotentPerPost(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// 首次推荐
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("author1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(10))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("author1", "post:recommend:p123").WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(30), "author1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "author1", "recommend", int64(20), int64(30), "帖子被推荐", "post:recommend:p123").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	tx, _ := db.Begin()
	if err := awardPointsTx(context.Background(), tx, "author1", "recommend", "帖子被推荐", "post:recommend:p123", 20, 0); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	// 取消推荐（不操作积分）
	// 再次推荐（幂等 key 已存在，不再发放）
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("author1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(30))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("author1", "post:recommend:p123").WillReturnRows(sqlmock.NewRows([]string{"balance_after"}).AddRow(30))
	mock.ExpectCommit()

	tx, _ = db.Begin()
	if err := awardPointsTx(context.Background(), tx, "author1", "recommend", "帖子被推荐", "post:recommend:p123", 20, 0); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestRecommendationBonusDoesNotConsumeDailyActivityQuota 验证推荐 +20 不会
// 抢占发帖/点赞共享的每日 +1 额度，且推荐后发帖仍可获得活动积分。
func TestRecommendationBonusDoesNotConsumeDailyActivityQuota(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// 推荐奖励不受每日额度限制。
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("author1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(100))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("author1", "post:recommend:p999").WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(120), "author1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "author1", "recommend", int64(20), int64(120), "帖子被推荐", "post:recommend:p999").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := awardPointsTx(context.Background(), tx, "author1", "recommend", "帖子被推荐", "post:recommend:p999", 20, 0); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}

	// 推荐后当天发帖，活动额度仍为 0/1，应发放 +1。
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("author1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(120))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("author1", "post:create:p999").WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COALESCE(SUM(delta), 0) FROM point_transactions WHERE user_id = $1 AND delta > 0 AND source IN ('post', 'like') AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`)).
		WithArgs("author1").WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(0))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(121), "author1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "author1", "post", int64(1), int64(121), "发布帖子", "post:create:p999").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()
	tx, err = db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := awardPointsTx(context.Background(), tx, "author1", "post", "发布帖子", "post:create:p999", 1, 1); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

// TestDailyPointReset 验证第二天可以重新获得 +1
func TestDailyPointReset(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// 第一天点赞
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT to_char(now() AT TIME ZONE 'Asia/Shanghai', 'YYYY-MM-DD')`)).
		WillReturnRows(sqlmock.NewRows([]string{"to_char"}).AddRow("2026-09-01"))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(0))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "daily:2026-09-01:user:u1").WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(1), "u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "u1", "like", int64(1), int64(1), "点赞帖子", "daily:2026-09-01:user:u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	tx, _ := db.Begin()
	if err := awardDailyPointTx(context.Background(), tx, "u1", "like", "点赞帖子", 1); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	// 第二天点赞（新的 key）
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT to_char(now() AT TIME ZONE 'Asia/Shanghai', 'YYYY-MM-DD')`)).
		WillReturnRows(sqlmock.NewRows([]string{"to_char"}).AddRow("2026-09-02"))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(1))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "daily:2026-09-02:user:u1").WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(2), "u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "u1", "like", int64(1), int64(2), "点赞帖子", "daily:2026-09-02:user:u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	tx, _ = db.Begin()
	if err := awardDailyPointTx(context.Background(), tx, "u1", "like", "点赞帖子", 1); err != nil {
		t.Fatal(err)
	}
	tx.Commit()

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
