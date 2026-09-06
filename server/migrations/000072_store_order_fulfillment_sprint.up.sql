-- 积分商城履约链路补全：
-- 1. 移除每位用户同时只能有一笔待审核兑换申请的限制（由可用积分与可用库存控制并发）。
-- 2. 为商城商品增加总库存、已预占、已发货履约字段及约束。
-- 3. 增加发货履约与完整地址查看权限。

DROP INDEX IF EXISTS store_orders_user_pending_review_idx;

ALTER TABLE store_products
    ADD COLUMN IF NOT EXISTS stock_total integer NOT NULL DEFAULT 100,
    ADD COLUMN IF NOT EXISTS stock_reserved integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS stock_fulfilled integer NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'store_products_stock_non_negative_check'
    ) THEN
        ALTER TABLE store_products
            ADD CONSTRAINT store_products_stock_non_negative_check
            CHECK (stock_total >= 0 AND stock_reserved >= 0 AND stock_fulfilled >= 0);
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'store_products_stock_capacity_check'
    ) THEN
        ALTER TABLE store_products
            ADD CONSTRAINT store_products_stock_capacity_check
            CHECK (stock_total >= stock_reserved + stock_fulfilled);
    END IF;
END;
$$;

INSERT INTO permissions (id, name)
VALUES 
    ('perm-store-order-fulfill', 'store.order.fulfill'),
    ('perm-store-order-shipping-view-full', 'store.order.shipping.view_full')
ON CONFLICT (id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT roles.role_id, perms.permission_id
FROM (VALUES ('role-platform-admin'), ('role-super-admin')) AS roles(role_id)
CROSS JOIN (VALUES ('perm-store-order-fulfill'), ('perm-store-order-shipping-view-full')) AS perms(permission_id)
ON CONFLICT DO NOTHING;
