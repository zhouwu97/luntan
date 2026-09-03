package api

import (
	"database/sql"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestPointRewardRulesMatchPublishedPolicy(t *testing.T) {
	rules := pointRewardRulesFromEnv()
	// 验证新的积分规则：
	// - 发帖 +10 积分
	// - 评论 +2 积分
	// - 点赞：每天前 5 个点赞各 +1 积分
	// - 每日总上限 20 积分
	// - 推荐奖励 +20 积分（不受每日上限限制）
	if rules.PostCreate != 10 || rules.CommentCreate != 2 || rules.LikeCreate != 1 || rules.LikeDailyLimit != 5 || rules.DailyEarnLimit != 20 || rules.RecommendationBonus != 20 {
		t.Fatalf("unexpected point policy: %+v", rules)
	}
}

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
	if err := awardPointsTx(t.Context(), tx, "u1", "post", "发布帖子", "post:create:p1", 10, 0); err != nil {
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
	if err := awardPointsTx(t.Context(), tx, "u1", "post", "发布帖子", "post:create:p1", 10, 0); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestAwardPointsTxRespectsDailyEarnLimit(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// 当日已得 18，奖励 5 只补齐到上限 20。
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(18))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "post:create:p2").WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COALESCE(SUM(delta), 0) FROM point_transactions WHERE user_id = $1 AND delta > 0 AND source IN ('post', 'like', 'comment') AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(18))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`)).
		WithArgs(int64(20), "u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs(sqlmock.AnyArg(), "u1", "post", int64(2), int64(20), "发布帖子", "post:create:p2").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := awardPointsTx(t.Context(), tx, "u1", "post", "发布帖子", "post:create:p2", 5, 20); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}

	// 达到上限后不再发放。
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"points_balance"}).AddRow(20))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "post:create:p3").WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COALESCE(SUM(delta), 0) FROM point_transactions WHERE user_id = $1 AND delta > 0 AND source IN ('post', 'like', 'comment') AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"coalesce"}).AddRow(20))
	mock.ExpectCommit()

	tx, err = db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := awardPointsTx(t.Context(), tx, "u1", "post", "发布帖子", "post:create:p3", 5, 20); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
