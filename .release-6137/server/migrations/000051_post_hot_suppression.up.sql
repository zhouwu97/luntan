ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS hot_suppressed boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS hot_suppressed_by text REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS hot_suppressed_at timestamptz,
  ADD COLUMN IF NOT EXISTS hot_suppressed_reason text DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_posts_hot_suppressed ON posts (hot_suppressed) WHERE hot_suppressed = true;
