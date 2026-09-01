CREATE TABLE IF NOT EXISTS users (
    id text PRIMARY KEY,
    username text NOT NULL,
    status text NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT users_username_unique UNIQUE (username)
);

CREATE TABLE IF NOT EXISTS user_profiles (
    user_id text PRIMARY KEY REFERENCES users(id),
    nickname text NOT NULL,
    avatar_media_id text,
    bio text NOT NULL DEFAULT '',
    level integer NOT NULL DEFAULT 1,
    experience integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
