ALTER TABLE media_assets
  ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS mask_regions jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS moderated_by text REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS moderated_at timestamptz,
  ADD COLUMN IF NOT EXISTS moderation_reason text DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_media_assets_moderation_status ON media_assets (moderation_status) WHERE moderation_status <> 'normal';
