-- 商品目录刷新（2026-08-29 产品确认）：
-- 保留论坛纪念徽章并调整为 60 积分；新增论坛纪念立牌 300 积分、200元杯子盲盒（可许愿）600 积分。
-- 主题贴纸包 / 校园钥匙扣 / 校园帆布袋下架：历史订单外键仍引用商品行，只能置 active=false 不能删除。
UPDATE store_products SET points = 60, updated_at = now() WHERE id = 'badge';

INSERT INTO store_products (id, name, description, emoji, points, color)
VALUES
    ('standee', '论坛纪念立牌', '论坛限定周边', '🪧', 300, 14273013),
    ('cup-blind-box', '200元杯子盲盒（可许愿）', '社区周边', '🥤', 600, 16765861)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    emoji = EXCLUDED.emoji,
    points = EXCLUDED.points,
    color = EXCLUDED.color,
    active = true,
    updated_at = now();

UPDATE store_products SET active = false, updated_at = now()
WHERE id IN ('stickers', 'keychain', 'tote')
  AND active = true;
