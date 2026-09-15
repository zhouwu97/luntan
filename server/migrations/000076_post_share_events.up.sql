CREATE TABLE IF NOT EXISTS post_share_events (
    post_id text NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

