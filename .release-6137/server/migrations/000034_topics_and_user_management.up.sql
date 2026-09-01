-- 内容主题必须是显式字段，不能再用“是否有图片”推断穿搭内容。
ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS topic text NOT NULL DEFAULT '';
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_topic_check;
ALTER TABLE posts
    ADD CONSTRAINT posts_topic_check CHECK (topic IN ('', 'outfit', 'activity', 'game_share'));
CREATE INDEX IF NOT EXISTS posts_topic_published_idx
    ON posts (topic, published_at DESC, id DESC)
    WHERE deleted_at IS NULL AND publication_status = 'published';

INSERT INTO permissions (id, name)
VALUES ('perm-user-manage', 'user.manage')
ON CONFLICT (name) DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id)
SELECT role_id, p.id
FROM (VALUES ('role-platform-admin'), ('role-super-admin')) AS roles(role_id)
JOIN permissions p ON p.name = 'user.manage'
ON CONFLICT DO NOTHING;
