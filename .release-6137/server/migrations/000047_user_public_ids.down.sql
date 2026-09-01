DROP TRIGGER IF EXISTS users_assign_public_id ON users;
DROP FUNCTION IF EXISTS assign_user_public_id();
DROP INDEX IF EXISTS users_public_id_unique_idx;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_public_id_range_check;
ALTER TABLE users DROP COLUMN IF EXISTS public_id;
DROP SEQUENCE IF EXISTS user_public_id_seq;
