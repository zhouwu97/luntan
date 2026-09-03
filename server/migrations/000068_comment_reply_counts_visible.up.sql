-- 外层回复数必须与楼中楼接口的可见回复集合一致。
CREATE INDEX IF NOT EXISTS comments_root_visible_created_idx
    ON comments (root_id, created_at ASC, id ASC)
    WHERE deleted_at IS NULL
      AND publication_status = 'published'
      AND moderation_status = 'normal';

-- 修复历史写入和审核恢复留下的冗余计数漂移。
UPDATE comments root
SET reply_count = (
    SELECT COUNT(*)
    FROM comments reply
    WHERE reply.root_id = root.id
      AND reply.id <> root.id
      AND reply.deleted_at IS NULL
      AND reply.publication_status = 'published'
      AND reply.moderation_status = 'normal'
)
WHERE root.root_id IS NULL OR root.root_id = root.id;

UPDATE ranking_toy_comments root
SET reply_count = (
    SELECT COUNT(*)
    FROM ranking_toy_comments reply
    WHERE reply.toy_id = root.toy_id
      AND COALESCE(reply.root_id, reply.id) = root.id
      AND reply.id <> root.id
      AND reply.deleted_at IS NULL
)
WHERE root.parent_id IS NULL;
