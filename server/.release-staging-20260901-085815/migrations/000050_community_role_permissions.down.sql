DELETE FROM role_permissions
WHERE role_id IN ('role-community-moderator', 'role-community-owner')
  AND permission_id IN (
      SELECT id
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
  );
