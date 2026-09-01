CREATE TABLE IF NOT EXISTS home_recommendations (
    post_id text PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,
    recommended_by text NOT NULL REFERENCES users(id),
    position integer NOT NULL DEFAULT 0,
    recommended_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz
);

CREATE INDEX IF NOT EXISTS home_recommendations_sort_idx ON home_recommendations (position ASC, recommended_at DESC, post_id DESC);

CREATE INDEX IF NOT EXISTS comments_post_valid_activity_idx ON comments (post_id, created_at DESC)
WHERE publication_status = 'published' AND moderation_status = 'normal' AND deleted_at IS NULL;
