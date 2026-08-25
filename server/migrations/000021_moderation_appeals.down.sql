DROP TABLE IF EXISTS moderation_appeal_media;
DROP TABLE IF EXISTS moderation_appeals;
ALTER TABLE moderation_actions DROP COLUMN IF EXISTS appealable;
