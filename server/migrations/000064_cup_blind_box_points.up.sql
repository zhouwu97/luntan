-- 杯子盲盒兑换积分调整为 1000，保留既有商品与订单引用。
UPDATE store_products
SET points = 1000, updated_at = now()
WHERE id = 'cup-blind-box';
