-- 兑换申请先冻结额度，管理员审核通过后才正式扣积分。
ALTER TABLE store_orders
    ADD COLUMN IF NOT EXISTS reviewed_by text REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
    ADD COLUMN IF NOT EXISTS review_reason text NOT NULL DEFAULT '';

-- 旧 pending 订单创建时已经扣过积分，固定为已扣分语义，避免新代码二次扣分。
UPDATE store_orders
SET status = 'approved'
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS store_orders_review_idx
    ON store_orders(status, created_at DESC, id DESC);

CREATE UNIQUE INDEX IF NOT EXISTS store_orders_user_pending_review_idx
    ON store_orders(user_id)
    WHERE status = 'pending_review';

INSERT INTO permissions (id, name)
VALUES ('perm-store-order-review', 'store.order.review')
ON CONFLICT (id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT role_id, 'perm-store-order-review'
FROM (VALUES ('role-platform-admin'), ('role-super-admin')) AS roles(role_id)
ON CONFLICT DO NOTHING;
