-- 社区角色必须拥有审核入口实际检查的权限，否则后台授权成功后仍无法处理社区案件。
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'role-community-moderator', id
FROM permissions
WHERE name IN (
    'post.hide.community',
    'comment.hide.community',
    'member.mute',
    'moderation.action',
    'report.review'
)
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'role-community-owner', id
FROM permissions
WHERE name IN (
    'post.hide.community',
    'comment.hide.community',
    'member.mute',
    'member.ban',
    'community.edit',
    'moderation.action',
    'report.review'
)
ON CONFLICT DO NOTHING;
