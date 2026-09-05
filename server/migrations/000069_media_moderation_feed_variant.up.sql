ALTER TABLE media_moderation_versions
    ADD COLUMN IF NOT EXISTS feed_object_key text NOT NULL DEFAULT '';

UPDATE media_moderation_versions mmv
SET feed_object_key = COALESCE((
    SELECT mv.object_key FROM media_variants mv
    WHERE mv.media_id = mmv.media_id AND mv.variant = CASE WHEN mmv.moderation_status = 'censored' THEN 'censored_feed' ELSE 'feed' END AND mv.status = 'ready'
), '')
WHERE feed_object_key = '';
