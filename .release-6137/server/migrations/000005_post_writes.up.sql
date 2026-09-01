CREATE TABLE IF NOT EXISTS post_revisions (
    id text PRIMARY KEY,
    post_id text NOT NULL REFERENCES posts(id),
    editor_id text NOT NULL REFERENCES users(id),
    community_id text NOT NULL REFERENCES communities(id),
    type text NOT NULL,
    title text NOT NULL,
    content text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS post_revisions_post_created_idx ON post_revisions (post_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS post_idempotency_keys (
    user_id text NOT NULL REFERENCES users(id),
    idempotency_key text NOT NULL,
    post_id text NOT NULL REFERENCES posts(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS post_idempotency_keys_created_idx ON post_idempotency_keys (created_at);
