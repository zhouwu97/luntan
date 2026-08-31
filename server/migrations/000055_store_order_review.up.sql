-- 兑换申请先冻结额度，管理员审核通过后才正式扣积分。
ALTER TABLE store_orders
    ADD COLUMN IF NOT EXISTS reviewed_by text REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
    ADD COLUMN IF NOT EXISTS review_reason text NOT NULL DEFAULT '';

-- 历史 pending 订单本来就是旧版已扣分、待领取订单，保留原语义；
-- 新代码只把新申请写成 pending_review，审核接口也不会处理 pending。

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

-- 评论目前没有独立修订表，用不可变快照保留“获得积分时”的原始内容。
-- 这样用户后续编辑或删除评论时，兑换审核仍能看到当时实际获得奖励的内容。
ALTER TABLE comments
    ADD COLUMN IF NOT EXISTS original_content text NOT NULL DEFAULT '';

UPDATE comments
SET original_content = content
WHERE original_content = '';

CREATE OR REPLACE FUNCTION preserve_comment_original_content() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.original_content := COALESCE(NULLIF(NEW.original_content, ''), NEW.content);
    ELSE
        NEW.original_content := COALESCE(NULLIF(OLD.original_content, ''), OLD.content);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS comments_original_content_snapshot ON comments;
CREATE TRIGGER comments_original_content_snapshot
BEFORE INSERT OR UPDATE ON comments
FOR EACH ROW EXECUTE FUNCTION preserve_comment_original_content();
