-- 一次性修复历史遗留孤儿回复：若根评价已软删除，将其名下尚未软删除的子回复一并软删除
UPDATE ranking_toy_comments child
SET deleted_at = now(),
    updated_at = now()
FROM ranking_toy_comments root
WHERE child.root_id = root.id
  AND root.deleted_at IS NOT NULL
  AND child.deleted_at IS NULL;
