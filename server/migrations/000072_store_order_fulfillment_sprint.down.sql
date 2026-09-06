DELETE FROM role_permissions WHERE permission_id IN ('perm-store-order-fulfill', 'perm-store-order-shipping-view-full');
DELETE FROM permissions WHERE id IN ('perm-store-order-fulfill', 'perm-store-order-shipping-view-full');

ALTER TABLE store_products
    DROP CONSTRAINT IF EXISTS store_products_stock_capacity_check,
    DROP CONSTRAINT IF EXISTS store_products_stock_non_negative_check,
    DROP COLUMN IF EXISTS stock_fulfilled,
    DROP COLUMN IF EXISTS stock_reserved,
    DROP COLUMN IF EXISTS stock_total;

CREATE UNIQUE INDEX IF NOT EXISTS store_orders_user_pending_review_idx
    ON store_orders(user_id)
    WHERE status = 'pending_review';
