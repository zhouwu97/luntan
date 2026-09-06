CREATE TABLE IF NOT EXISTS post_view_events (
    post_id text NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    viewer_key varchar(160) NOT NULL,
    view_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, viewer_key, view_date)
);

CREATE INDEX IF NOT EXISTS post_view_events_date_idx ON post_view_events (view_date);
