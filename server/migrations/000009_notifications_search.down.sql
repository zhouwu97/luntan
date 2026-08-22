DROP TABLE IF EXISTS notifications;
ALTER TABLE posts DROP COLUMN IF EXISTS search_vector;
ALTER TABLE communities DROP COLUMN IF EXISTS search_vector;
ALTER TABLE users DROP COLUMN IF EXISTS search_vector;
