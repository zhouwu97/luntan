CREATE TABLE IF NOT EXISTS comments (
    id text PRIMARY KEY,
    post_id text NOT NULL REFERENCES posts(id),
    author_id text NOT NULL REFERENCES users(id),
    root_id text,
    parent_id text REFERENCES comments(id),
    reply_to_user_id text REFERENCES users(id),
    content text NOT NULL,
    like_count bigint NOT NULL DEFAULT 0,
    reply_count bigint NOT NULL DEFAULT 0,
    publication_status text NOT NULL DEFAULT 'published',
    moderation_status text NOT NULL DEFAULT 'normal',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS comments_post_created_idx ON comments (post_id, created_at ASC, id ASC);
CREATE INDEX IF NOT EXISTS comments_parent_created_idx ON comments (parent_id, created_at ASC, id ASC);
CREATE INDEX IF NOT EXISTS comments_author_created_idx ON comments (author_id, created_at DESC, id DESC);
