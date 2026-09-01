ALTER TABLE user_profiles
    ADD COLUMN IF NOT EXISTS trust_level text NOT NULL DEFAULT 'new';

CREATE INDEX IF NOT EXISTS user_profiles_trust_level_idx
    ON user_profiles (trust_level, updated_at DESC);
