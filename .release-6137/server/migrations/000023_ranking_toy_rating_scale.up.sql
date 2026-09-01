-- 将 000022 中按十分位写入的历史汇总值转换为 centi 口径。
-- 后续评分接口统一按 score * 100 累加，保证平均分保持 0-10 的一位小数。
UPDATE ranking_toys
SET rating_total_centi = rating_total_centi * 10,
    updated_at = now()
WHERE rating_count > 0;
