DROP INDEX IF EXISTS idx_media_assets_moderation_status;
ALTER TABLE media_assets
  DROP COLUMN IF EXISTS moderation_status,
  DROP COLUMN IF EXISTS mask_regions,
  DROP COLUMN IF EXISTS moderated_by,
  DROP COLUMN IF EXISTS moderated_at,
  DROP COLUMN IF EXISTS moderation_reason;
