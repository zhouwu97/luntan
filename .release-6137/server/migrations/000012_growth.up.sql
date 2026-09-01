ALTER TABLE users ADD COLUMN IF NOT EXISTS points_balance bigint NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS point_transactions (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    source text NOT NULL,
    delta bigint NOT NULL,
    balance_after bigint NOT NULL,
    reason text NOT NULL DEFAULT '',
    idempotency_key text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS point_transactions_user_idempotency_idx ON point_transactions (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS point_transactions_user_created_idx ON point_transactions (user_id, created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS polls (
    id text PRIMARY KEY,
    post_id text NOT NULL UNIQUE REFERENCES posts(id),
    question text NOT NULL,
    allow_multiple boolean NOT NULL DEFAULT false,
    ends_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS poll_options (
    id text PRIMARY KEY,
    poll_id text NOT NULL REFERENCES polls(id),
    label text NOT NULL,
    sort_order integer NOT NULL,
    vote_count bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (poll_id, sort_order)
);

CREATE TABLE IF NOT EXISTS poll_votes (
    poll_id text NOT NULL REFERENCES polls(id),
    option_id text NOT NULL REFERENCES poll_options(id),
    user_id text NOT NULL REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (poll_id, option_id, user_id)
);

CREATE OR REPLACE FUNCTION enforce_poll_vote_choice() RETURNS trigger AS $$
BEGIN
    -- 同一用户在单选投票上的并发写入必须串行化，避免两个事务同时通过 EXISTS 检查。
    PERFORM pg_advisory_xact_lock(hashtext(NEW.poll_id || ':' || NEW.user_id));
    IF NOT (SELECT allow_multiple FROM polls WHERE id = NEW.poll_id)
       AND EXISTS (SELECT 1 FROM poll_votes WHERE poll_id = NEW.poll_id AND user_id = NEW.user_id) THEN
        RAISE EXCEPTION 'poll allows only one option per user';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS poll_votes_single_choice_trigger ON poll_votes;
CREATE TRIGGER poll_votes_single_choice_trigger
BEFORE INSERT ON poll_votes
FOR EACH ROW EXECUTE FUNCTION enforce_poll_vote_choice();

CREATE TABLE IF NOT EXISTS market_items (
    id text PRIMARY KEY,
    post_id text NOT NULL UNIQUE REFERENCES posts(id),
    seller_id text NOT NULL REFERENCES users(id),
    price numeric(12, 2) NOT NULL,
    currency text NOT NULL DEFAULT 'CNY',
    item_condition text NOT NULL,
    sold boolean NOT NULL DEFAULT false,
    delivery text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS market_items_active_idx ON market_items (sold, updated_at DESC);
