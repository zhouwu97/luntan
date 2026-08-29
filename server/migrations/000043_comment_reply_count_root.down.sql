-- 回滚为历史语义：reply_count 统计直接子评论（尽力恢复）。
UPDATE comments c
SET reply_count = (
    SELECT COUNT(*) FROM comments d
    WHERE d.parent_id = c.id AND d.deleted_at IS NULL
);
