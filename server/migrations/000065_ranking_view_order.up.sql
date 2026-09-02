-- 榜单展示排序覆盖层：管理员可为每个 tab+category 视图独立启用人工排序，
-- 源排名（ranking_toys.rank / ranking_toy_rankings.rank）保持只读，
-- 外部榜单重新导入不会覆盖人工顺序。
CREATE TABLE IF NOT EXISTS ranking_view_settings (
    tab_key text NOT NULL DEFAULT '',
    category_key text NOT NULL DEFAULT '',
    sort_mode text NOT NULL DEFAULT 'AUTO',
    version bigint NOT NULL DEFAULT 0,
    updated_by text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tab_key, category_key),
    CONSTRAINT ranking_view_settings_mode_check CHECK (sort_mode IN ('AUTO', 'MANUAL'))
);

CREATE TABLE IF NOT EXISTS ranking_manual_orders (
    tab_key text NOT NULL DEFAULT '',
    category_key text NOT NULL DEFAULT '',
    toy_id text NOT NULL REFERENCES ranking_toys(id) ON DELETE CASCADE,
    position integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tab_key, category_key, toy_id),
    CONSTRAINT ranking_manual_orders_position_check CHECK (position > 0)
);

CREATE INDEX IF NOT EXISTS ranking_manual_orders_view_position_idx
    ON ranking_manual_orders (tab_key, category_key, position ASC);
