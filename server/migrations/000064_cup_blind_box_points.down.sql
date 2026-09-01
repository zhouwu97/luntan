-- 回滚杯子盲盒的兑换积分。
UPDATE store_products
SET points = 600, updated_at = now()
WHERE id = 'cup-blind-box';
