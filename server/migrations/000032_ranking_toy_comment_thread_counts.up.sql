CREATE INDEX IF NOT EXISTS ranking_toy_comments_root_created_idx
    ON ranking_toy_comments (toy_id, root_id, created_at ASC, id ASC);

-- reply_count 统一表示整座楼的回复数，而不是只统计直接子节点。
UPDATE ranking_toy_comments root
SET reply_count = (
    SELECT count(*)
    FROM ranking_toy_comments child
    WHERE child.toy_id = root.toy_id
      AND COALESCE(child.root_id, child.id) = root.id
      AND child.id <> root.id
      AND child.deleted_at IS NULL
)
WHERE root.deleted_at IS NULL
  AND root.parent_id IS NULL;
