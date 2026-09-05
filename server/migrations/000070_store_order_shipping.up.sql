-- 积分商城审核后进入履约链路：先收货信息，再发货，再完成。
ALTER TABLE store_orders
    ADD COLUMN IF NOT EXISTS fulfillment_status text NOT NULL DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS shipped_at timestamptz,
    ADD COLUMN IF NOT EXISTS completed_at timestamptz;

UPDATE store_orders
SET fulfillment_status = CASE
    WHEN status = 'approved' THEN 'awaiting_address'
    WHEN status = 'claimed' THEN 'shipped'
    WHEN status = 'completed' THEN 'completed'
    WHEN status = 'cancelled' THEN 'cancelled'
    ELSE 'none'
END
WHERE fulfillment_status = 'none';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'store_orders_fulfillment_status_check'
    ) THEN
        ALTER TABLE store_orders
            ADD CONSTRAINT store_orders_fulfillment_status_check
            CHECK (fulfillment_status IN ('none', 'awaiting_address', 'ready_to_ship', 'shipped', 'completed', 'cancelled'));
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS store_order_shipping (
    id text PRIMARY KEY,
    order_id text NOT NULL UNIQUE REFERENCES store_orders(id) ON DELETE CASCADE,
    recipient_name text NOT NULL,
    phone text NOT NULL,
    province text NOT NULL,
    city text NOT NULL,
    district text NOT NULL DEFAULT '',
    address_detail text NOT NULL,
    carrier text NOT NULL DEFAULT '',
    tracking_no text NOT NULL DEFAULT '',
    submitted_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS store_orders_fulfillment_idx
    ON store_orders(fulfillment_status, updated_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS store_order_shipping_order_idx
    ON store_order_shipping(order_id);
