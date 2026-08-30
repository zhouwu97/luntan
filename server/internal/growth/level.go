// Package growth 提供论坛账号统一的等级阈值计算。
package growth

const MaxUserLevel = 8

// levelThresholds 参考 SYLUlive MCP 分支的全站等级口径。
// 下标即等级，值为达到该等级所需的累计经验。
var levelThresholds = [...]int64{
	0,    // 占位，等级从 1 开始
	0,    // Lv.1
	50,   // Lv.2
	150,  // Lv.3
	500,  // Lv.4
	1000, // Lv.5
	2500, // Lv.6
	5000, // Lv.7
	8000, // Lv.8
}

// LevelStartExperience 返回达到指定等级所需的累计经验。
func LevelStartExperience(level int) int64 {
	if level <= 1 {
		return 0
	}
	if level > MaxUserLevel {
		level = MaxUserLevel
	}
	return levelThresholds[level]
}

// LevelForExperience 返回正式账号的当前等级；游客等级由调用方固定为 Lv.0。
func LevelForExperience(exp int64) int {
	if exp <= 0 {
		return 1
	}
	for level := MaxUserLevel; level >= 1; level-- {
		if exp >= LevelStartExperience(level) {
			return level
		}
	}
	return 1
}
