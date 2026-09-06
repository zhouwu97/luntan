-- 有进行中的售后时禁止静默回退，避免丢失资金和物流状态。
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM store_orders WHERE fulfillment_status IN ('return_requested', 'refund_pending', 'refunded')) THEN
        RAISE EXCEPTION '存在售后订单，不能回退售后迁移';
    END IF;
END $$;
DROP TABLE store_order_reverse_requests;
ALTER TABLE store_orders
    DROP COLUMN reverse_previous_status, DROP COLUMN reverse_reason,
    DROP COLUMN return_instructions, DROP COLUMN return_carrier,
    DROP COLUMN return_tracking_no, DROP COLUMN refunded_points;
ALTER TABLE store_orders DROP CONSTRAINT store_orders_fulfillment_status_check;
ALTER TABLE store_orders ADD CONSTRAINT store_orders_fulfillment_status_check
    CHECK (fulfillment_status IN ('none', 'awaiting_address', 'ready_to_ship', 'shipped', 'completed', 'cancelled'));
