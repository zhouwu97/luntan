CREATE TABLE IF NOT EXISTS outbox_events (
    id text PRIMARY KEY,
    event_type text NOT NULL,
    aggregate_type text NOT NULL,
    aggregate_id text NOT NULL,
    payload jsonb NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    attempts integer NOT NULL DEFAULT 0,
    available_at timestamptz NOT NULL DEFAULT now(),
    locked_at timestamptz,
    processed_at timestamptz,
    last_error text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT outbox_events_status_check CHECK (status IN ('pending', 'processing', 'succeeded', 'failed'))
);

CREATE UNIQUE INDEX IF NOT EXISTS outbox_events_dedupe_idx ON outbox_events (event_type, aggregate_type, aggregate_id, created_at);
CREATE INDEX IF NOT EXISTS outbox_events_ready_idx ON outbox_events (status, available_at, created_at, id);
