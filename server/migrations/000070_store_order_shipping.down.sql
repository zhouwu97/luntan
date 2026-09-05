DROP INDEX IF EXISTS store_order_shipping_order_idx;
DROP INDEX IF EXISTS store_orders_fulfillment_idx;
DROP TABLE IF EXISTS store_order_shipping;

ALTER TABLE store_orders
    DROP CONSTRAINT IF EXISTS store_orders_fulfillment_status_check,
    DROP COLUMN IF EXISTS completed_at,
    DROP COLUMN IF EXISTS shipped_at,
    DROP COLUMN IF EXISTS fulfillment_status;
