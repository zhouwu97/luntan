CREATE TABLE IF NOT EXISTS user_auth_methods (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    provider text NOT NULL,
    identifier text NOT NULL,
    credential_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz,
    CONSTRAINT user_auth_methods_provider_identifier_unique UNIQUE (provider, identifier)
);

CREATE INDEX IF NOT EXISTS user_auth_methods_user_id_idx ON user_auth_methods (user_id);

CREATE TABLE IF NOT EXISTS sessions (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    access_token_hash text NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    user_agent text NOT NULL DEFAULT '',
    ip_address text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sessions_user_active_idx ON sessions (user_id, revoked_at, expires_at);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id text PRIMARY KEY,
    session_id text NOT NULL REFERENCES sessions(id),
    user_id text NOT NULL REFERENCES users(id),
    token_hash text NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    replaced_by_id text REFERENCES refresh_tokens(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS refresh_tokens_session_idx ON refresh_tokens (session_id);
CREATE INDEX IF NOT EXISTS refresh_tokens_expiry_idx ON refresh_tokens (expires_at, revoked_at);
