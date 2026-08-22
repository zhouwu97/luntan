CREATE TABLE IF NOT EXISTS posts (
    id text PRIMARY KEY,
    author_id text NOT NULL REFERENCES users(id),
    community_id text NOT NULL REFERENCES communities(id),
    type text NOT NULL DEFAULT 'normal',
    publication_status text NOT NULL DEFAULT 'draft',
    moderation_status text NOT NULL DEFAULT 'normal',
    title text NOT NULL,
    content text NOT NULL,
    comment_count bigint NOT NULL DEFAULT 0,
    like_count bigint NOT NULL DEFAULT 0,
    bookmark_count bigint NOT NULL DEFAULT 0,
    share_count bigint NOT NULL DEFAULT 0,
    view_count bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS posts_community_published_id_idx ON posts (community_id, published_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS posts_author_published_id_idx ON posts (author_id, published_at DESC, id DESC);
