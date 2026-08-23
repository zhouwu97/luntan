ALTER TABLE store_orders
    ADD COLUMN IF NOT EXISTS idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS store_orders_user_idempotency_idx
    ON store_orders (user_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
