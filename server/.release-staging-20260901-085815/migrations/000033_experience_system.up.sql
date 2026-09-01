ALTER TABLE user_profiles
ALTER COLUMN experience TYPE bigint
USING experience::bigint;

UPDATE user_profiles up
SET level = 0
FROM users u
WHERE up.user_id = u.id
  AND u.account_type = 'guest';

CREATE TABLE IF NOT EXISTS experience_transactions (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    source text NOT NULL,
    delta bigint NOT NULL,
    experience_after bigint NOT NULL,
    reason text NOT NULL DEFAULT '',
    idempotency_key text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS experience_transactions_user_idempotency_idx
ON experience_transactions(user_id, idempotency_key)
WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS experience_transactions_user_created_idx
ON experience_transactions(user_id, created_at DESC, id DESC);
