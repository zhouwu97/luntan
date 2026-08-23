CREATE TABLE IF NOT EXISTS user_post_histories (
    user_id text NOT NULL REFERENCES users(id),
    post_id text NOT NULL REFERENCES posts(id),
    viewed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, post_id)
);

CREATE INDEX IF NOT EXISTS user_post_histories_user_viewed_idx
    ON user_post_histories (user_id, viewed_at DESC, post_id DESC);
