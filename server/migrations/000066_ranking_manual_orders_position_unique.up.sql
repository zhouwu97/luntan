-- 同一视图内人工位次必须唯一：写入路径是全量 DELETE + 1..N 重插，
-- 唯一索引只在数据库层兜底，防止并发写坏出同位次的两条记录。
CREATE UNIQUE INDEX IF NOT EXISTS ranking_manual_orders_position_unique
    ON ranking_manual_orders (tab_key, category_key, position);
