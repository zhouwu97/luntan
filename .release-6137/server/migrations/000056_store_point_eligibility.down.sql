DROP INDEX IF EXISTS store_point_invalidations_order_idx;
DROP INDEX IF EXISTS store_point_invalidations_user_idx;
DROP TABLE IF EXISTS store_point_invalidations;

ALTER TABLE store_orders
    DROP COLUMN IF EXISTS balance_at_submit;
