ALTER TABLE risk_events
    DROP CONSTRAINT IF EXISTS risk_events_user_id_fkey;

ALTER TABLE risk_events
    ADD CONSTRAINT risk_events_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id);

