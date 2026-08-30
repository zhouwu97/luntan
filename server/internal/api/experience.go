package api

import (
	"context"
	"database/sql"
	"errors"
	"math"

	"github.com/zhouwu97/luntan/server/internal/growth"
)

const maxUserLevel = growth.MaxUserLevel

// ExperienceRewardRules 集中管理经验奖励与每日上限。
type ExperienceRewardRules struct {
	PostCreate              int64
	PostCreateDailyLimit    int
	CommentCreate           int64
	CommentCreateDailyLimit int
}

func defaultExperienceRewardRules() ExperienceRewardRules {
	return ExperienceRewardRules{
		PostCreate:              20,
		PostCreateDailyLimit:    3,
		CommentCreate:           5,
		CommentCreateDailyLimit: 10,
	}
}

// levelStartExperience 返回达到指定等级所需的累计经验。
// 兼容现有 API 包内调用，权威阈值统一维护在 internal/growth。
func levelStartExperience(level int) int64 {
	return growth.LevelStartExperience(level)
}

// levelForExperience 根据累计经验计算正式用户的当前等级（最高 8 级）。
func levelForExperience(exp int64) int {
	return growth.LevelForExperience(exp)
}

// GrowthState 提供统一的经验与等级计算结果。
type GrowthState struct {
	Level                     int      `json:"level"`
	Experience                int64    `json:"experience"`
	LevelStartExperience      int64    `json:"level_start_experience"`
	NextLevelExperience       *int64   `json:"next_level_experience"`
	ExperienceInLevel         int64    `json:"experience_in_level"`
	ExperienceRequiredInLevel *int64   `json:"experience_required_in_level"`
	LevelProgress             *float64 `json:"level_progress"`
	LevelLocked               bool     `json:"level_locked"`
}

// growthState 计算给定身份与经验的完整成长状态。
func growthState(accountType string, exp int64) GrowthState {
	if exp < 0 {
		exp = 0
	}
	if accountType == "guest" {
		return GrowthState{
			Level:                     0,
			Experience:                exp,
			LevelStartExperience:      0,
			NextLevelExperience:       nil,
			ExperienceInLevel:         exp,
			ExperienceRequiredInLevel: nil,
			LevelProgress:             nil,
			LevelLocked:               true,
		}
	}

	level := levelForExperience(exp)
	startExp := levelStartExperience(level)
	inLevel := exp - startExp

	if level >= maxUserLevel {
		progress := 1.0
		return GrowthState{
			Level:                     maxUserLevel,
			Experience:                exp,
			LevelStartExperience:      startExp,
			NextLevelExperience:       nil,
			ExperienceInLevel:         inLevel,
			ExperienceRequiredInLevel: nil,
			LevelProgress:             &progress,
			LevelLocked:               false,
		}
	}

	nextExp := levelStartExperience(level + 1)
	reqInLevel := nextExp - startExp
	progress := math.Round((float64(inLevel)/float64(reqInLevel))*1000) / 1000

	return GrowthState{
		Level:                     level,
		Experience:                exp,
		LevelStartExperience:      startExp,
		NextLevelExperience:       &nextExp,
		ExperienceInLevel:         inLevel,
		ExperienceRequiredInLevel: &reqInLevel,
		LevelProgress:             &progress,
		LevelLocked:               false,
	}
}

// awardExperienceTx 在调用方事务内完成经验奖励、等级刷新与流水落库，支持幂等与每日次数上限。
func awardExperienceTx(ctx context.Context, tx *sql.Tx, userID, source, reason, idempotencyKey string, delta int64, dailyLimit int) error {
	if delta <= 0 || tx == nil {
		return nil
	}

	// 1. 用户与个人资料行锁
	var currentExp int64
	var accountType string
	err := tx.QueryRowContext(ctx, `
		SELECT COALESCE(up.experience, 0), COALESCE(u.account_type, 'email')
		FROM users u
		LEFT JOIN user_profiles up ON up.user_id = u.id
		WHERE u.id = $1
		FOR UPDATE OF u`, userID).Scan(&currentExp, &accountType)
	if err != nil {
		return err
	}

	// 2. 幂等性检查
	if idempotencyKey != "" {
		var existingBalance int64
		err := tx.QueryRowContext(ctx, `
			SELECT experience_after
			FROM experience_transactions
			WHERE user_id = $1 AND idempotency_key = $2`, userID, idempotencyKey).Scan(&existingBalance)
		if err == nil {
			return nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
	}

	// 3. 每日上限检查（按 UTC 当日零点统计该 source 产生的奖励次数）
	if dailyLimit > 0 {
		var countToday int
		err := tx.QueryRowContext(ctx, `
			SELECT count(*)
			FROM experience_transactions
			WHERE user_id = $1 AND source = $2 AND created_at >= date_trunc('day', now() AT TIME ZONE 'UTC')`, userID, source).Scan(&countToday)
		if err != nil {
			return err
		}
		if countToday >= dailyLimit {
			return nil
		}
	}

	// 4. 计算新经验与新等级
	newExp := currentExp + delta
	newLevel := 0
	if accountType != "guest" {
		newLevel = levelForExperience(newExp)
	}

	// 5. 更新 user_profiles
	if _, err := tx.ExecContext(ctx, `
		UPDATE user_profiles
		SET experience = $1, level = $2, updated_at = now()
		WHERE user_id = $3`, newExp, newLevel, userID); err != nil {
		return err
	}

	// 6. 写入流水
	txID := newPostID()
	_, err = tx.ExecContext(ctx, `
		INSERT INTO experience_transactions (id, user_id, source, delta, experience_after, reason, idempotency_key, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, now())`, txID, userID, source, delta, newExp, reason, idempotencyKey)
	return err
}
