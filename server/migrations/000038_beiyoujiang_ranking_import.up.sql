-- 杯友酱公开榜单的原始数据、图片和评价均落在本库。source_* 只标识导入
-- 来源；前端始终通过本项目 API 读取，不再依赖源站资源。
ALTER TABLE ranking_toys
    ADD COLUMN IF NOT EXISTS source_provider text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS source_toy_id text,
    ADD COLUMN IF NOT EXISTS source_updated_at timestamptz,
    ADD COLUMN IF NOT EXISTS source_want_count bigint NOT NULL DEFAULT 0 CHECK (source_want_count >= 0),
    ADD COLUMN IF NOT EXISTS source_rating_total_centi bigint NOT NULL DEFAULT 0 CHECK (source_rating_total_centi >= 0),
    ADD COLUMN IF NOT EXISTS source_rating_count bigint NOT NULL DEFAULT 0 CHECK (source_rating_count >= 0),
    ADD COLUMN IF NOT EXISTS cover_media_id text REFERENCES media_assets(id),
    ADD COLUMN IF NOT EXISTS hero_media_id text REFERENCES media_assets(id),
    ADD COLUMN IF NOT EXISTS coupon_url text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS source_url text NOT NULL DEFAULT '';

CREATE UNIQUE INDEX IF NOT EXISTS ranking_toys_source_provider_toy_id_idx
    ON ranking_toys (source_provider, source_toy_id)
    WHERE source_provider <> '' AND source_toy_id IS NOT NULL;

-- 一个商品可同时出现在不同的训练标签及品类视图；名次必须按该视图
-- 的原始返回顺序保存，不能用评分或总榜 rank 在客户端重新排序。
CREATE TABLE IF NOT EXISTS ranking_toy_rankings (
    source_provider text NOT NULL,
    view_key text NOT NULL,
    tab_key text NOT NULL DEFAULT '',
    category_key text NOT NULL DEFAULT '',
    toy_id text NOT NULL REFERENCES ranking_toys(id) ON DELETE CASCADE,
    rank integer NOT NULL CHECK (rank > 0),
    is_weekly_top boolean NOT NULL DEFAULT false,
    snapshot_fetched_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (source_provider, view_key, toy_id),
    UNIQUE (source_provider, view_key, rank)
);

CREATE INDEX IF NOT EXISTS ranking_toy_rankings_view_order_idx
    ON ranking_toy_rankings (source_provider, tab_key, category_key, rank ASC);

ALTER TABLE ranking_toy_comments
    ADD COLUMN IF NOT EXISTS source_provider text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS source_comment_id text;

CREATE UNIQUE INDEX IF NOT EXISTS ranking_toy_comments_source_identity_idx
    ON ranking_toy_comments (source_provider, toy_id, source_comment_id)
    WHERE source_provider <> '' AND source_comment_id IS NOT NULL;

-- 评价配图不再以源站 URL 存在 JSON 中，而是关联到本项目 media_assets。
CREATE TABLE IF NOT EXISTS ranking_toy_comment_media (
    comment_id text NOT NULL REFERENCES ranking_toy_comments(id) ON DELETE CASCADE,
    media_id text NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
    sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (comment_id, media_id)
);

CREATE INDEX IF NOT EXISTS ranking_toy_comment_media_comment_order_idx
    ON ranking_toy_comment_media (comment_id, sort_order ASC);

-- 保留“源站基线 + 本站用户增量”。重同步源站时不会冲掉本站用户的
-- 想冲、评分和评分明细。
ALTER TABLE ranking_toy_rating_distribution
    ADD COLUMN IF NOT EXISTS source_rating_count bigint NOT NULL DEFAULT 0 CHECK (source_rating_count >= 0);
