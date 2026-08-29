-- 楼中楼计数语义修正：根评论 reply_count 统计整层楼中楼的全部可见后代，
-- 与 GET /comments/{root}/replies 的返回集一致；非根评论不再维护 reply_count。
UPDATE comments c
SET reply_count = (
    SELECT COUNT(*) FROM comments d
    WHERE d.root_id = c.id AND d.id <> c.id AND d.deleted_at IS NULL
      AND d.publication_status = 'published' AND d.moderation_status = 'normal'
)
WHERE c.root_id IS NULL OR c.root_id = c.id;

UPDATE comments c
SET reply_count = 0
WHERE c.root_id IS NOT NULL AND c.root_id <> c.id AND c.reply_count <> 0;
