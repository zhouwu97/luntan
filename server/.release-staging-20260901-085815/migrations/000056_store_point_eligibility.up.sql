-- 兑换审核使用申请提交时的积分快照，避免审核期间新获得的积分改变本次资格。
ALTER TABLE store_orders
    ADD COLUMN IF NOT EXISTS balance_at_submit bigint;

-- 迁移前创建的订单无法恢复真实提交时余额，至少保留当前余额作为兼容快照；
-- 新版 pending_review 订单会在创建时显式写入该字段。
UPDATE store_orders o
SET balance_at_submit = u.points_balance
FROM users u
WHERE o.user_id = u.id
  AND o.balance_at_submit IS NULL;

ALTER TABLE store_orders
    ALTER COLUMN balance_at_submit SET DEFAULT 0,
    ALTER COLUMN balance_at_submit SET NOT NULL;

-- 无效的是“某笔奖励流水在兑换资格中的用途”，不是帖子或评论本身的属性。
CREATE TABLE IF NOT EXISTS store_point_invalidations (
    point_transaction_id text PRIMARY KEY REFERENCES point_transactions(id),
    user_id text NOT NULL REFERENCES users(id),
    source_order_id text REFERENCES store_orders(id),
    reason text NOT NULL,
    reviewed_by text NOT NULL REFERENCES users(id),
    reviewed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS store_point_invalidations_user_idx
    ON store_point_invalidations(user_id, reviewed_at DESC, point_transaction_id);

CREATE INDEX IF NOT EXISTS store_point_invalidations_order_idx
    ON store_point_invalidations(source_order_id);
