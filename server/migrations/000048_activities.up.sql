CREATE TABLE IF NOT EXISTS activities (
    id text PRIMARY KEY,
    title text NOT NULL,
    description text NOT NULL DEFAULT '',
    cover_media_id text REFERENCES media_assets(id) ON DELETE SET NULL,
    cover_url text NOT NULL DEFAULT '',
    start_at timestamptz,
    end_at timestamptz,
    location text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'upcoming', 'active', 'ended', 'offline')),
    created_by text NOT NULL REFERENCES users(id),
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS activities_status_idx ON activities (status, published_at DESC, id DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS activities_public_idx ON activities (published_at DESC, id DESC) WHERE deleted_at IS NULL AND status IN ('upcoming', 'active', 'ended');
