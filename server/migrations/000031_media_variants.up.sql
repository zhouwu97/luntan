CREATE TABLE IF NOT EXISTS media_variants (
    media_id text NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
    variant text NOT NULL, -- 'source', 'original', 'detail', 'thumb'
    object_key text NOT NULL,
    mime_type text NOT NULL,
    width integer NOT NULL DEFAULT 0,
    height integer NOT NULL DEFAULT 0,
    size_bytes bigint NOT NULL DEFAULT 0,
    sha256 text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'ready',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (media_id, variant)
);

CREATE INDEX IF NOT EXISTS media_variants_media_id_idx ON media_variants (media_id);
