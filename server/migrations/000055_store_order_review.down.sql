DROP INDEX IF EXISTS store_orders_user_pending_review_idx;
DROP INDEX IF EXISTS store_orders_review_idx;

DELETE FROM role_permissions WHERE permission_id = 'perm-store-order-review';
DELETE FROM permissions WHERE id = 'perm-store-order-review';

DROP TRIGGER IF EXISTS comments_original_content_snapshot ON comments;
DROP FUNCTION IF EXISTS preserve_comment_original_content();

ALTER TABLE comments
    DROP COLUMN IF EXISTS original_content;

ALTER TABLE store_orders
    DROP COLUMN IF EXISTS reviewed_by,
    DROP COLUMN IF EXISTS reviewed_at,
    DROP COLUMN IF EXISTS review_reason;
