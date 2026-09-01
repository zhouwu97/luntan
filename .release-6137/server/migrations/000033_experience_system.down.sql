DROP TABLE IF EXISTS experience_transactions;

ALTER TABLE user_profiles
ALTER COLUMN experience TYPE integer
USING experience::integer;
