package api

import (
	"context"
	"database/sql"
	"os"
	"strconv"
	"strings"
)

// PointRewardRules 将奖励数值集中在一个配置对象中。默认值保持为 0，
// 等产品确认规则后只需通过环境变量调整，不把业务数字散落在发帖/评论事务里。
type PointRewardRules struct {
	PostCreate    int64
	CommentCreate int64
}

func pointRewardRulesFromEnv() PointRewardRules {
	return PointRewardRules{
		PostCreate:    envInt64("POINT_REWARD_POST_CREATE"),
		CommentCreate: envInt64("POINT_REWARD_COMMENT_CREATE"),
	}
}

func envInt64(key string) int64 {
	value, err := strconv.ParseInt(strings.TrimSpace(os.Getenv(key)), 10, 64)
	if err != nil || value < 0 {
		return 0
	}
	return value
}

// awardPointsTx 在调用方事务内完成余额更新与流水落库。
// idempotencyKey 必须由业务事件 ID 构成，弱网重试只会命中已有流水而不会重复加分。
func awardPointsTx(ctx context.Context, tx *sql.Tx, userID, source, reason, idempotencyKey string, delta int64) error {
	if delta == 0 {
		return nil
	}
	var balance int64
	if err := tx.QueryRowContext(ctx, `SELECT points_balance FROM users WHERE id = $1 FOR UPDATE`, userID).Scan(&balance); err != nil {
		return err
	}
	// 必须在用户行锁建立后再检查一次。否则两个相同事件并发时，
	// 两个事务都可能先读到“没有流水”，随后第二个事务会撞上唯一索引。
	var existingBalance int64
	err := tx.QueryRowContext(ctx, `SELECT balance_after FROM point_transactions WHERE user_id = $1 AND idempotency_key = $2`, userID, idempotencyKey).Scan(&existingBalance)
	if err == nil {
		return nil
	}
	if err != sql.ErrNoRows {
		return err
	}
	newBalance := balance + delta
	if _, err := tx.ExecContext(ctx, `UPDATE users SET points_balance = $1, updated_at = now() WHERE id = $2`, newBalance, userID); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO point_transactions (id, user_id, source, delta, balance_after, reason, idempotency_key) VALUES ($1, $2, $3, $4, $5, $6, $7)`, newPostID(), userID, source, delta, newBalance, reason, idempotencyKey)
	return err
}
