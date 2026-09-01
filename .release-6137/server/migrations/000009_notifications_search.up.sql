CREATE TABLE IF NOT EXISTS notifications (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    type text NOT NULL,
    actor_id text REFERENCES users(id),
    target_type text NOT NULL,
    target_id text NOT NULL,
    is_read boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    read_at timestamptz
);

CREATE INDEX IF NOT EXISTS notifications_user_created_idx ON notifications (user_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS notifications_unread_idx ON notifications (user_id, is_read, created_at DESC);

ALTER TABLE users ADD COLUMN IF NOT EXISTS search_vector tsvector GENERATED ALWAYS AS (to_tsvector('simple', coalesce(username, ''))) STORED;
ALTER TABLE communities ADD COLUMN IF NOT EXISTS search_vector tsvector GENERATED ALWAYS AS (to_tsvector('simple', coalesce(name, '') || ' ' || coalesce(description, ''))) STORED;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS search_vector tsvector GENERATED ALWAYS AS (to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(content, ''))) STORED;

CREATE INDEX IF NOT EXISTS users_search_vector_gin_idx ON users USING GIN (search_vector);
CREATE INDEX IF NOT EXISTS communities_search_vector_gin_idx ON communities USING GIN (search_vector);
CREATE INDEX IF NOT EXISTS posts_search_vector_gin_idx ON posts USING GIN (search_vector);
