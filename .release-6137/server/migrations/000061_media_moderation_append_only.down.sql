DROP TRIGGER IF EXISTS media_moderation_versions_append_only ON media_moderation_versions;
DROP FUNCTION IF EXISTS prevent_media_moderation_version_mutation();
DROP INDEX IF EXISTS media_moderation_versions_snapshot_idx;

ALTER TABLE media_moderation_versions
    DROP CONSTRAINT IF EXISTS media_moderation_versions_media_id_fkey;

ALTER TABLE media_moderation_versions
    ALTER COLUMN media_id SET NOT NULL;

ALTER TABLE media_moderation_versions
    ADD CONSTRAINT media_moderation_versions_media_id_fkey
    FOREIGN KEY (media_id) REFERENCES media_assets(id) ON DELETE CASCADE;

ALTER TABLE media_moderation_versions
    DROP COLUMN IF EXISTS media_id_snapshot;

