-- 迁移前订单只能用迁移时余额近似提交快照，不能作为严格审核依据。
ALTER TABLE store_orders
    ADD COLUMN IF NOT EXISTS balance_snapshot_trusted boolean NOT NULL DEFAULT true;

UPDATE store_orders
SET balance_snapshot_trusted = false
WHERE balance_snapshot_trusted = true;

