package api

import (
	"testing"
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
