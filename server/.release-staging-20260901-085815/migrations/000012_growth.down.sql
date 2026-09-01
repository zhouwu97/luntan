DROP TABLE IF EXISTS market_items;
DROP TRIGGER IF EXISTS poll_votes_single_choice_trigger ON poll_votes;
DROP FUNCTION IF EXISTS enforce_poll_vote_choice();
DROP TABLE IF EXISTS poll_votes;
DROP TABLE IF EXISTS poll_options;
DROP TABLE IF EXISTS polls;
DROP TABLE IF EXISTS point_transactions;
ALTER TABLE users DROP COLUMN IF EXISTS points_balance;
