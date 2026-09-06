-- 已发布的历史活动不补发全站广播；新活动首次发布才通知。
ALTER TABLE activities ADD COLUMN notification_sent_at timestamptz;
UPDATE activities SET notification_sent_at = COALESCE(published_at, updated_at) WHERE published_at IS NOT NULL OR publication_status = 'published';
-- 修复存量关注通知，客户端和待投递事件使用相同目标。
UPDATE notifications SET target_id = actor_id WHERE type IN ('follow', 'user.followed') AND target_type = 'user' AND actor_id IS NOT NULL AND actor_id <> '' AND target_id <> actor_id;
UPDATE outbox_events SET payload = jsonb_set(payload, '{target_id}', payload->'actor_id')
WHERE event_type = 'notification.created' AND payload->>'type' IN ('follow', 'user.followed')
  AND payload->>'target_type' = 'user' AND COALESCE(payload->>'actor_id', '') <> '';
CREATE TABLE community_announcements (
    id text PRIMARY KEY,
    actor_id text NOT NULL REFERENCES users(id),
    title text NOT NULL,
    content text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
