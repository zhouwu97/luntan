ALTER TABLE notifications
    ADD COLUMN IF NOT EXISTS target_data jsonb;
