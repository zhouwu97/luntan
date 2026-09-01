DROP INDEX IF EXISTS ranking_toy_comments_parent_created_idx;
ALTER TABLE ranking_toy_comments
    DROP COLUMN IF EXISTS reply_count,
    DROP COLUMN IF EXISTS reply_to_user_id,
    DROP COLUMN IF EXISTS parent_id,
    DROP COLUMN IF EXISTS root_id;
