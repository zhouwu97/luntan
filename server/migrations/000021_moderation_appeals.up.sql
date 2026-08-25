ALTER TABLE moderation_actions
    ADD COLUMN IF NOT EXISTS appealable boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS moderation_appeals (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    moderation_action_id text NOT NULL UNIQUE REFERENCES moderation_actions(id),
    target_type text NOT NULL,
    target_id text NOT NULL,
    reason text NOT NULL,
    description text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'pending',
    reviewer_id text REFERENCES users(id),
    reviewer_note text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    reviewed_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT moderation_appeals_status_check CHECK (status IN ('pending', 'reviewing', 'approved', 'rejected', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS moderation_appeals_user_created_idx
    ON moderation_appeals (user_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS moderation_appeals_status_created_idx
    ON moderation_appeals (status, created_at ASC, id ASC);

CREATE TABLE IF NOT EXISTS moderation_appeal_media (
    appeal_id text NOT NULL REFERENCES moderation_appeals(id) ON DELETE CASCADE,
    media_id text NOT NULL REFERENCES media_assets(id),
    position integer NOT NULL DEFAULT 0,
    PRIMARY KEY (appeal_id, media_id)
);

CREATE INDEX IF NOT EXISTS moderation_appeal_media_position_idx
    ON moderation_appeal_media (appeal_id, position ASC);
