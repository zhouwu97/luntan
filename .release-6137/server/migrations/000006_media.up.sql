CREATE TABLE IF NOT EXISTS media_assets (
    id text PRIMARY KEY,
    owner_id text NOT NULL REFERENCES users(id),
    object_key text NOT NULL UNIQUE,
    original_name text NOT NULL,
    mime_type text NOT NULL,
    width integer NOT NULL DEFAULT 0,
    height integer NOT NULL DEFAULT 0,
    size bigint NOT NULL,
    sha256 text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    deleted_at timestamptz,
    CONSTRAINT media_assets_status_check CHECK (status IN ('pending', 'ready', 'failed', 'deleted'))
);

CREATE INDEX IF NOT EXISTS media_assets_owner_status_idx ON media_assets (owner_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS media_assets_orphan_idx ON media_assets (status, updated_at);

CREATE TABLE IF NOT EXISTS post_media (
    post_id text NOT NULL REFERENCES posts(id),
    media_id text NOT NULL REFERENCES media_assets(id),
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, media_id)
);

CREATE INDEX IF NOT EXISTS post_media_media_id_idx ON post_media (media_id);
