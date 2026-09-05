-- 该迁移需要为历史版本记录补齐 feed 变体 key；media_moderation_versions
-- 已经在 000061 后变为 append-only，因此回填期间短暂关闭本表保护触发器。
ALTER TABLE media_moderation_versions
    DISABLE TRIGGER media_moderation_versions_append_only;

ALTER TABLE media_moderation_versions
    ADD COLUMN IF NOT EXISTS feed_object_key text NOT NULL DEFAULT '';

UPDATE media_moderation_versions mmv
SET feed_object_key = COALESCE((
    SELECT mv.object_key FROM media_variants mv
    WHERE mv.media_id = mmv.media_id AND mv.variant = CASE WHEN mmv.moderation_status = 'censored' THEN 'censored_feed' ELSE 'feed' END AND mv.status = 'ready'
), '')
WHERE feed_object_key = '';

ALTER TABLE media_moderation_versions
    ENABLE TRIGGER media_moderation_versions_append_only;
