DROP INDEX IF EXISTS user_profiles_trust_level_idx;
ALTER TABLE user_profiles DROP COLUMN IF EXISTS trust_level;
