-- 媒体打码版本链：第 1 版固定为初始发布状态，后续每次打码或恢复都追加新版本。
-- 版本记录只追加、不更新、不删除，便于审核追溯和事故复盘。
CREATE TABLE IF NOT EXISTS media_moderation_versions (
    id text PRIMARY KEY,
    media_id text NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
    version_no integer NOT NULL CHECK (version_no > 0),
    moderation_status text NOT NULL CHECK (moderation_status IN ('normal', 'censored')),
    mask_regions jsonb NOT NULL DEFAULT '[]'::jsonb,
    original_object_key text NOT NULL DEFAULT '',
    detail_object_key text NOT NULL DEFAULT '',
    thumb_object_key text NOT NULL DEFAULT '',
    operator_id text REFERENCES users(id),
    reason text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (media_id, version_no)
);

CREATE INDEX IF NOT EXISTS media_moderation_versions_media_idx
    ON media_moderation_versions (media_id, version_no ASC);

-- 为存量媒体补齐初始发布快照。若媒体已有正常变体，优先记录当时的
-- original/detail/thumb 变体；否则回退到 media_assets.object_key。
INSERT INTO media_moderation_versions (
    id, media_id, version_no, moderation_status, mask_regions,
    original_object_key, detail_object_key, thumb_object_key,
    operator_id, reason, created_at
)
SELECT
    md5(random()::text || clock_timestamp()::text || ma.id),
    ma.id,
    1,
    'normal',
    '[]'::jsonb,
    COALESCE((SELECT mv.object_key FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'original' AND mv.status = 'ready'), ma.object_key),
    COALESCE((SELECT mv.object_key FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'detail' AND mv.status = 'ready'), ''),
    COALESCE((SELECT mv.object_key FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'thumb' AND mv.status = 'ready'), ''),
    NULL,
    '初始发布状态',
    ma.created_at
FROM media_assets ma
WHERE NOT EXISTS (
    SELECT 1 FROM media_moderation_versions mmv
    WHERE mmv.media_id = ma.id AND mmv.version_no = 1
);

-- 存量媒体如果已经是 censored，补记当前打码快照作为第 2 版；
-- 新安装不会命中这条语句，后续由业务事务追加版本。
INSERT INTO media_moderation_versions (
    id, media_id, version_no, moderation_status, mask_regions,
    original_object_key, detail_object_key, thumb_object_key,
    operator_id, reason, created_at
)
SELECT
    md5(random()::text || clock_timestamp()::text || ma.id || ':censored'),
    ma.id,
    2,
    'censored',
    COALESCE(ma.mask_regions, '[]'::jsonb),
    COALESCE((SELECT mv.object_key FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'censored_original' AND mv.status = 'ready'), ''),
    COALESCE((SELECT mv.object_key FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'censored_detail' AND mv.status = 'ready'), ''),
    COALESCE((SELECT mv.object_key FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'censored_thumb' AND mv.status = 'ready'), ''),
    ma.moderated_by,
    COALESCE(NULLIF(ma.moderation_reason, ''), '历史打码状态'),
    COALESCE(ma.moderated_at, ma.updated_at, ma.created_at)
FROM media_assets ma
WHERE ma.moderation_status = 'censored'
  AND NOT EXISTS (
      SELECT 1 FROM media_moderation_versions mmv
      WHERE mmv.media_id = ma.id AND mmv.version_no = 2
  );
