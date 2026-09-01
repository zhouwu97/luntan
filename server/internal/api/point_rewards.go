package api

import (
	"context"
	"database/sql"
)

// PointRewardRules 集中管理积分奖励与每日获取上限。
// 产品已确认：发帖 +1、点赞 +1，每日最多获得 1 积分；评论不再发放积分。
// 帖子被管理员推荐一次性奖励作者 +20，不受每日上限限制，取消推荐不扣分。
// 这是用户可见的固定规则，不允许环境变量造成页面文案与实际发放不一致。
type PointRewardRules struct {
	PostCreate          int64
	LikeCreate          int64
	DailyEarnLimit      int64
	RecommendationBonus int64
}

func defaultPointRewardRules() PointRewardRules {
	return PointRewardRules{
		PostCreate:          1,
		LikeCreate:          1,
		DailyEarnLimit:      1,
		RecommendationBonus: 20,
	}
}

func pointRewardRulesFromEnv() PointRewardRules {
	return defaultPointRewardRules()
}

// awardPointsTx 在调用方事务内完成余额更新与流水落库。
// idempotencyKey 必须由业务事件 ID 构成，弱网重试只会命中已有流水而不会重复加分。
// dailyEarnLimit 为每日正向奖励上限（0 表示不限制）；兑换扣分是负向流水，不占用额度，
// 当日剩余额度不足时按剩余额度发放。
func awardPointsTx(ctx context.Context, tx *sql.Tx, userID, source, reason, idempotencyKey string, delta int64, dailyEarnLimit int64) error {
	if delta == 0 {
		return nil
	}
	var balance int64
	if err := tx.QueryRowContext(ctx, `SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&balance); err != nil {
		return err
	}
	// 必须在用户行锁建立后再检查一次。否则两个相同事件并发时，
	// 两个事务都可能先读到”没有流水”，随后第二个事务会撞上唯一索引。
	var existingBalance int64
	err := tx.QueryRowContext(ctx, `SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`, userID, idempotencyKey).Scan(&existingBalance)
	if err == nil {
		return nil
	}
	if err != sql.ErrNoRows {
		return err
	}
	if dailyEarnLimit > 0 && delta > 0 {
		var earnedToday int64
		// 自然日按北京时间计算，与用户感知的”一天”一致；
		// 双重 AT TIME ZONE 把上海零点正确还原成 timestamptz，不受会话时区影响。
		if err := tx.QueryRowContext(ctx, `SELECT COALESCE(SUM(delta), 0) FROM point_transactions WHERE user_id = $1 AND delta > 0 AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`, userID).Scan(&earnedToday); err != nil {
			return err
		}
		if earnedToday >= dailyEarnLimit {
			return nil
		}
		if remaining := dailyEarnLimit - earnedToday; remaining < delta {
			delta = remaining
		}
	}
	newBalance := balance + delta
	if _, err := tx.ExecContext(ctx, `UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`, newBalance, userID); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`, newPostID(), userID, source, delta, newBalance, reason, idempotencyKey)
	return err
}

// awardDailyPointTx 为每日积分入口统一发放积分，所有入口（点赞、发帖等）竞争同一份每日额度。
// 幂等键格式为 daily:YYYY-MM-DD:user:userID，确保用户每天只能通过任一入口获得一次奖励。
// source 用于审计流水来源（”like” 或 “post”），但不影响幂等性。
func awardDailyPointTx(ctx context.Context, tx *sql.Tx, userID, source, reason string, delta int64) error {
	if delta == 0 {
		return nil
	}
	// 计算业务日期（北京时间的自然日）
	var bizDate string
	if err := tx.QueryRowContext(ctx, `SELECT to_char(now() AT TIME ZONE 'Asia/Shanghai', 'YYYY-MM-DD')`).Scan(&bizDate); err != nil {
		return err
	}
	idempotencyKey := "daily:" + bizDate + ":user:" + userID
	return awardPointsTx(ctx, tx, userID, source, reason, idempotencyKey, delta, 0)
}
