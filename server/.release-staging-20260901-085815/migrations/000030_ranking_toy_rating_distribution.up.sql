-- 评分汇总、评分人数和分布必须来自同一套可更新事实。
-- 旧版本只有 rating_total_centi/rating_count，先按已展示的一位小数还原一组
-- 相邻整数评分，保证总人数一致，平均分按当前 UI 规则四舍五入后保持不变。
CREATE TABLE IF NOT EXISTS ranking_toy_rating_distribution (
    toy_id text NOT NULL REFERENCES ranking_toys(id) ON DELETE CASCADE,
    score integer NOT NULL CHECK (score >= 1 AND score <= 10),
    rating_count bigint NOT NULL DEFAULT 0 CHECK (rating_count >= 0),
    PRIMARY KEY (toy_id, score)
);

WITH targets AS (
    SELECT
        id,
        rating_count,
        ROUND(rating_total_centi / 100.0)::bigint AS target_sum
    FROM ranking_toys
    WHERE rating_count > 0
), buckets AS (
    SELECT
        id,
        rating_count,
        target_sum,
        GREATEST(1, LEAST(10, target_sum / rating_count)) AS base_score,
        target_sum % rating_count AS remainder
    FROM targets
)
INSERT INTO ranking_toy_rating_distribution (toy_id, score, rating_count)
SELECT
    buckets.id,
    scores.score,
    CASE
        WHEN scores.score = buckets.base_score
            THEN buckets.rating_count - buckets.remainder
        WHEN scores.score = buckets.base_score + 1
            THEN buckets.remainder
        ELSE 0
    END
FROM buckets
CROSS JOIN generate_series(1, 10) AS scores(score)
ON CONFLICT (toy_id, score) DO UPDATE
SET rating_count = EXCLUDED.rating_count;

-- 将汇总总分校正为分布的加权总分，避免历史一位小数反推时出现 0.1 分舍入漂移。
UPDATE ranking_toys AS toys
SET rating_total_centi = COALESCE((
        SELECT SUM(distribution.score * distribution.rating_count) * 100
        FROM ranking_toy_rating_distribution AS distribution
        WHERE distribution.toy_id = toys.id
    ), 0),
    updated_at = now()
WHERE toys.rating_count > 0;

CREATE INDEX IF NOT EXISTS ranking_toy_rating_distribution_toy_idx
    ON ranking_toy_rating_distribution (toy_id, score);
