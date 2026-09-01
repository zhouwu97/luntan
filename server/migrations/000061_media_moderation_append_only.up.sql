-- 媒体审核版本链保留原始媒体 ID 快照，即使媒体记录日后被删除也能追溯。
ALTER TABLE media_moderation_versions
    ADD COLUMN IF NOT EXISTS media_id_snapshot text;

UPDATE media_moderation_versions
SET media_id_snapshot = media_id
WHERE media_id_snapshot IS NULL;

ALTER TABLE media_moderation_versions
    ALTER COLUMN media_id_snapshot SET NOT NULL;

DO $$
DECLARE
    constraint_name text;
BEGIN
    SELECT conname
      INTO constraint_name
      FROM pg_constraint
     WHERE conrelid = 'media_moderation_versions'::regclass
       AND confrelid = 'media_assets'::regclass
       AND contype = 'f'
     LIMIT 1;
    IF constraint_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE media_moderation_versions DROP CONSTRAINT %I', constraint_name);
    END IF;
END $$;

ALTER TABLE media_moderation_versions
    ALTER COLUMN media_id DROP NOT NULL;

ALTER TABLE media_moderation_versions
    ADD CONSTRAINT media_moderation_versions_media_id_fkey
    FOREIGN KEY (media_id) REFERENCES media_assets(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS media_moderation_versions_snapshot_idx
    ON media_moderation_versions (media_id_snapshot, version_no ASC);

CREATE OR REPLACE FUNCTION prevent_media_moderation_version_mutation() RETURNS trigger AS $$
BEGIN
    -- ON DELETE SET NULL 通过更新子表 media_id 保留审核快照；允许这一种
    -- 仅改变外键列的系统维护动作，其他审计字段仍严格不可变。
    IF TG_OP = 'UPDATE'
       AND OLD.media_id IS NOT NULL
       AND NEW.media_id IS NULL
       AND NEW.media_id_snapshot = OLD.media_id_snapshot
       AND NEW.id = OLD.id
       AND NEW.version_no = OLD.version_no
       AND NEW.moderation_status = OLD.moderation_status
       AND NEW.mask_regions = OLD.mask_regions
       AND NEW.original_object_key = OLD.original_object_key
       AND NEW.detail_object_key = OLD.detail_object_key
       AND NEW.thumb_object_key = OLD.thumb_object_key
       AND NEW.operator_id IS NOT DISTINCT FROM OLD.operator_id
       AND NEW.reason = OLD.reason
       AND NEW.created_at = OLD.created_at THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'media moderation versions are append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS media_moderation_versions_append_only ON media_moderation_versions;
CREATE TRIGGER media_moderation_versions_append_only
BEFORE UPDATE OR DELETE ON media_moderation_versions
FOR EACH ROW EXECUTE FUNCTION prevent_media_moderation_version_mutation();
