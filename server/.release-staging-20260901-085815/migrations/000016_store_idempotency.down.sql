DROP INDEX IF EXISTS store_orders_user_idempotency_idx;
ALTER TABLE store_orders DROP COLUMN IF EXISTS idempotency_key;
