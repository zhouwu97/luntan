package api

import (
	"database/sql"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestLevelForExperience(t *testing.T) {
	cases := []struct {
		exp      int64
		expected int
	}{
		{-10, 1},
		{0, 1},
		{49, 1},
		{50, 2},
		{149, 2},
		{150, 3},
		{499, 3},
		{500, 4},
		{999, 4},
		{1000, 5},
		{2499, 5},
		{2500, 6},
		{4999, 6},
		{5000, 7},
		{7999, 7},
		{8000, 8},
		{99999, 8},
	}

	for _, c := range cases {
		got := levelForExperience(c.exp)
		if got != c.expected {
			t.Errorf("levelForExperience(%d) = %d; want %d", c.exp, got, c.expected)
		}
	}
}

func TestGrowthState(t *testing.T) {
	// 游客测试
	guestState := growthState("guest", 860)
	if guestState.Level != 0 {
		t.Errorf("guest level = %d; want 0", guestState.Level)
	}
	if guestState.Experience != 860 {
		t.Errorf("guest exp = %d; want 860", guestState.Experience)
	}
	if !guestState.LevelLocked {
		t.Errorf("guest level_locked = %v; want true", guestState.LevelLocked)
	}
	if guestState.NextLevelExperience != nil {
		t.Errorf("guest next_level_exp = %v; want nil", guestState.NextLevelExperience)
	}
	if guestState.LevelProgress != nil {
		t.Errorf("guest progress = %v; want nil", guestState.LevelProgress)
	}

	// Lv.4 (860 EXP) 正式用户
	userState := growthState("email", 860)
	if userState.Level != 4 {
		t.Errorf("user level = %d; want 4", userState.Level)
	}
	if userState.LevelStartExperience != 500 {
		t.Errorf("user start exp = %d; want 500", userState.LevelStartExperience)
	}
	if userState.NextLevelExperience == nil || *userState.NextLevelExperience != 1000 {
		t.Errorf("user next exp = %v; want 1000", userState.NextLevelExperience)
	}
	if userState.ExperienceInLevel != 360 {
		t.Errorf("user in level = %d; want 360", userState.ExperienceInLevel)
	}
	if userState.ExperienceRequiredInLevel == nil || *userState.ExperienceRequiredInLevel != 500 {
		t.Errorf("user req in level = %v; want 500", userState.ExperienceRequiredInLevel)
	}
	if userState.LevelProgress == nil || *userState.LevelProgress != 0.72 {
		t.Errorf("user progress = %v; want 0.72", userState.LevelProgress)
	}
	if userState.LevelLocked {
		t.Errorf("user level_locked = %v; want false", userState.LevelLocked)
	}

	// 满级 Lv.8 (8000 EXP)
	maxState := growthState("email", 8000)
	if maxState.Level != 8 {
		t.Errorf("max user level = %d; want 8", maxState.Level)
	}
	if maxState.NextLevelExperience != nil {
		t.Errorf("max user next exp = %v; want nil", maxState.NextLevelExperience)
	}
	if maxState.LevelProgress == nil || *maxState.LevelProgress != 1.0 {
		t.Errorf("max user progress = %v; want 1.0", maxState.LevelProgress)
	}
}

func TestAwardExperienceTxUsesShanghaiDayBoundary(t *testing.T) {
	// 经验每日次数限制必须与积分每日上限共用北京时间自然日；
	// 精确匹配 SQL，防止回退成 UTC 日界在北京时间早上 8 点前后错位。
	const shanghaiCountQuery = `SELECT count(*) FROM experience_transactions WHERE user_id = $1 AND source = $2 AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Shanghai') AT TIME ZONE 'Asia/Shanghai'`

	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// 当日已发 2 次（上限 3）：第 3 次照常发放，860 + 20 = 880 仍是 Lv.4。
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COALESCE(up.experience, 0), COALESCE(u.account_type, 'email') FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id WHERE u.id = $1 FOR UPDATE OF u`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"experience", "account_type"}).AddRow(860, "email"))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT experience_after FROM experience_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "post:create:p1").WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(shanghaiCountQuery)).
		WithArgs("u1", "post").WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(2))
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE user_profiles SET experience = $1, level = $2, updated_at = now() WHERE user_id = $3`)).
		WithArgs(int64(880), 4, "u1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta(`INSERT INTO experience_transactions (id, user_id, source, delta, experience_after, reason, idempotency_key, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, now())`)).
		WithArgs(sqlmock.AnyArg(), "u1", "post", int64(20), int64(880), "发布帖子", "post:create:p1").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := awardExperienceTx(t.Context(), tx, "u1", "post", "发布帖子", "post:create:p1", 20, 3); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}

	// 当日已发 3 次（达到上限）：静默不发，不再写 user_profiles / 流水。
	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT COALESCE(up.experience, 0), COALESCE(u.account_type, 'email') FROM users u LEFT JOIN user_profiles up ON up.user_id = u.id WHERE u.id = $1 FOR UPDATE OF u`)).
		WithArgs("u1").WillReturnRows(sqlmock.NewRows([]string{"experience", "account_type"}).AddRow(880, "email"))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT experience_after FROM experience_transactions WHERE user_id = $1 AND idempotency_key = $2`)).
		WithArgs("u1", "post:create:p2").WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(regexp.QuoteMeta(shanghaiCountQuery)).
		WithArgs("u1", "post").WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(3))
	mock.ExpectCommit()

	tx, err = db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := awardExperienceTx(t.Context(), tx, "u1", "post", "发布帖子", "post:create:p2", 20, 3); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
