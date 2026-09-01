DROP INDEX IF EXISTS idx_posts_hot_suppressed;
ALTER TABLE posts
  DROP COLUMN IF EXISTS hot_suppressed,
  DROP COLUMN IF EXISTS hot_suppressed_by,
  DROP COLUMN IF EXISTS hot_suppressed_at,
  DROP COLUMN IF EXISTS hot_suppressed_reason;
