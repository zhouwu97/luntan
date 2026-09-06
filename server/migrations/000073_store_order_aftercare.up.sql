-- 售后独立于审核结论，取消与退款不会抹掉原审核记录。
-- 旧版审核订单可能早于库存计数上线，补足已承诺数量；仅补账，不增加可兑换余量。
WITH committed AS (
    SELECT p.id,
        GREATEST(p.stock_reserved, COUNT(o.id) FILTER (WHERE o.fulfillment_status IN ('awaiting_address', 'ready_to_ship')))::integer AS reserved,
        GREATEST(p.stock_fulfilled, COUNT(o.id) FILTER (WHERE o.fulfillment_status IN ('shipped', 'completed')))::integer AS fulfilled
    FROM store_products p LEFT JOIN store_orders o ON o.product_id = p.id AND o.status = 'approved'
    GROUP BY p.id
)
UPDATE store_products p SET stock_reserved = c.reserved, stock_fulfilled = c.fulfilled,
    stock_total = GREATEST(p.stock_total, c.reserved + c.fulfilled)
FROM committed c WHERE c.id = p.id;

ALTER TABLE store_orders DROP CONSTRAINT store_orders_fulfillment_status_check;
ALTER TABLE store_orders ADD CONSTRAINT store_orders_fulfillment_status_check
    CHECK (fulfillment_status IN ('none', 'awaiting_address', 'ready_to_ship', 'shipped', 'completed', 'cancelled', 'return_requested', 'refund_pending', 'refunded'));
ALTER TABLE store_orders
    ADD COLUMN reverse_previous_status text NOT NULL DEFAULT '',
    ADD COLUMN reverse_reason text NOT NULL DEFAULT '',
    ADD COLUMN return_instructions text NOT NULL DEFAULT '',
    ADD COLUMN return_carrier text NOT NULL DEFAULT '',
    ADD COLUMN return_tracking_no text NOT NULL DEFAULT '',
    ADD COLUMN refunded_points bigint NOT NULL DEFAULT 0 CHECK (refunded_points >= 0);

-- 保存请求而非仅保存按钮动作；弱网重试不能重复退款或重复释放库存。
CREATE TABLE store_order_reverse_requests (
    order_id text NOT NULL REFERENCES store_orders(id) ON DELETE CASCADE,
    actor_id text NOT NULL REFERENCES users(id),
    idempotency_key text NOT NULL,
    request jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (order_id, actor_id, idempotency_key)
);
