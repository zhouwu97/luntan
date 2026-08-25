ALTER TABLE ranking_toy_comments
    ADD COLUMN IF NOT EXISTS root_id text,
    ADD COLUMN IF NOT EXISTS parent_id text,
    ADD COLUMN IF NOT EXISTS reply_to_user_id text REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS reply_count bigint NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS ranking_toy_comments_parent_created_idx
    ON ranking_toy_comments (parent_id, created_at ASC, id ASC);

UPDATE ranking_toy_comments
SET root_id = id
WHERE root_id IS NULL;

INSERT INTO ranking_toy_comments (
    id, toy_id, author_id, content, root_id, parent_id, reply_to_user_id, like_count
)
VALUES (
    'toy-comment-yingchuan-1-reply',
    'toy-yingchuan-2',
    'ranking-reviewer-2',
    '这条我也遇到过，普通版和经典版的包装标识要看清楚，软度差异可以先看大家的实测记录。',
    'toy-comment-yingchuan-1',
    'toy-comment-yingchuan-1',
    'ranking-reviewer-1',
    1
)
ON CONFLICT (id) DO UPDATE SET content = EXCLUDED.content, updated_at = now();

UPDATE ranking_toy_comments parent
SET reply_count = (
    SELECT count(*) FROM ranking_toy_comments child
    WHERE child.parent_id = parent.id AND child.deleted_at IS NULL
)
WHERE parent.id = 'toy-comment-yingchuan-1';
