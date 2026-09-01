DELETE FROM role_permissions
WHERE permission_id = (SELECT id FROM permissions WHERE name = 'user.manage');
DELETE FROM permissions WHERE name = 'user.manage';
DROP INDEX IF EXISTS posts_topic_published_idx;
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_topic_check;
ALTER TABLE posts DROP COLUMN IF EXISTS topic;
