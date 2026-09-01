-- 平台治理增强：邮箱验证码、游客身份、处罚约束、风控与不可篡改管理员日志。
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS email text,
    ADD COLUMN IF NOT EXISTS email_verified boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS email_verified_at timestamptz,
    ADD COLUMN IF NOT EXISTS account_type text NOT NULL DEFAULT 'email';

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_account_type_check;
ALTER TABLE users
    ADD CONSTRAINT users_account_type_check CHECK (account_type IN ('email', 'guest'));
CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique_idx
    ON users (lower(email)) WHERE email IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS users_account_type_created_idx
    ON users (account_type, created_at DESC);

CREATE TABLE IF NOT EXISTS email_codes (
    id text PRIMARY KEY,
    email text NOT NULL,
    purpose text NOT NULL DEFAULT 'login',
    code_hash text NOT NULL,
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz,
    attempts integer NOT NULL DEFAULT 0,
    requested_ip text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT email_codes_purpose_check CHECK (purpose IN ('login', 'verify'))
);
CREATE INDEX IF NOT EXISTS email_codes_lookup_idx
    ON email_codes (lower(email), purpose, created_at DESC);
CREATE INDEX IF NOT EXISTS email_codes_expiry_idx
    ON email_codes (expires_at, consumed_at);

CREATE TABLE IF NOT EXISTS guest_sessions (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    session_id text NOT NULL UNIQUE REFERENCES sessions(id),
    ip_address text NOT NULL DEFAULT '',
    user_agent text NOT NULL DEFAULT '',
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS guest_sessions_user_idx
    ON guest_sessions (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS bans (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    operator_id text REFERENCES users(id),
    scope text NOT NULL DEFAULT 'platform',
    reason text NOT NULL,
    starts_at timestamptz NOT NULL DEFAULT now(),
    ends_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS bans_user_active_idx
    ON bans (user_id, starts_at DESC, ends_at);

ALTER TABLE moderation_actions
    ADD COLUMN IF NOT EXISTS duration_days integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS starts_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS ends_at timestamptz;

CREATE TABLE IF NOT EXISTS restrictions (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    restriction_type text NOT NULL,
    limit_value integer NOT NULL,
    window_seconds integer NOT NULL,
    reason text NOT NULL DEFAULT '',
    starts_at timestamptz NOT NULL DEFAULT now(),
    ends_at timestamptz,
    operator_id text REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS restrictions_user_active_idx
    ON restrictions (user_id, restriction_type, starts_at DESC, ends_at);

CREATE TABLE IF NOT EXISTS admin_invites (
    id text PRIMARY KEY,
    email text NOT NULL,
    role_id text NOT NULL REFERENCES roles(id),
    invited_by text NOT NULL REFERENCES users(id),
    token_hash text NOT NULL UNIQUE,
    expires_at timestamptz NOT NULL,
    accepted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS admin_invites_email_idx
    ON admin_invites (lower(email), expires_at DESC);

CREATE TABLE IF NOT EXISTS login_devices (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    session_id text REFERENCES sessions(id),
    fingerprint text NOT NULL,
    ip_address text NOT NULL DEFAULT '',
    user_agent text NOT NULL DEFAULT '',
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS login_devices_user_fingerprint_idx
    ON login_devices (user_id, fingerprint);

CREATE TABLE IF NOT EXISTS risk_events (
    id text PRIMARY KEY,
    user_id text REFERENCES users(id),
    event_type text NOT NULL,
    severity text NOT NULL DEFAULT 'low',
    ip_address text NOT NULL DEFAULT '',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS risk_events_created_idx
    ON risk_events (created_at DESC, severity);
CREATE INDEX IF NOT EXISTS risk_events_user_idx
    ON risk_events (user_id, created_at DESC);

ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS post_status text NOT NULL DEFAULT 'published';
ALTER TABLE posts
    DROP CONSTRAINT IF EXISTS posts_post_status_check;
ALTER TABLE posts
    ADD CONSTRAINT posts_post_status_check CHECK (post_status IN ('pending', 'published', 'hidden', 'deleted', 'reviewing'));
CREATE INDEX IF NOT EXISTS posts_post_status_idx
    ON posts (post_status, created_at DESC);

-- 第一版自动审核使用规则，不依赖 AI：广告词、群聊入口、手机号、淘宝链接和外链
-- 进入待审核；新账号每日第一条内容可直接发布，超出额度自动进入待审核队列。
CREATE OR REPLACE FUNCTION apply_forum_content_rules() RETURNS trigger AS $$
DECLARE
    account_created_at timestamptz;
    today_count integer;
    suspicious boolean;
    case_id text;
BEGIN
    SELECT created_at INTO account_created_at FROM users WHERE id = NEW.author_id;
    suspicious := NEW.content ~* '(微信群|QQ群|加微信|加 ?QQ|淘宝|taobao\.com|https?://|(^|[^0-9])[0-9]{11}([^0-9]|$))';
    SELECT count(*) INTO today_count
      FROM posts
     WHERE author_id = NEW.author_id AND created_at >= date_trunc('day', now());
    IF suspicious OR (account_created_at IS NOT NULL AND account_created_at > now() - interval '24 hours' AND today_count >= 1) THEN
        case_id := md5(random()::text || clock_timestamp()::text);
        NEW.post_status := 'pending';
        NEW.moderation_status := 'pending';
        NEW.moderation_case_id := case_id;
        INSERT INTO moderation_cases (id, target_type, target_id, source, risk_level, status)
        VALUES (case_id, 'post', NEW.id, 'auto_rule', 'medium', 'open');
        INSERT INTO risk_events (id, user_id, event_type, severity, metadata)
        VALUES (md5(random()::text || clock_timestamp()::text), NEW.author_id, 'content_auto_review', 'medium', jsonb_build_object('target_type', 'post'));
    ELSE
        NEW.post_status := COALESCE(NULLIF(NEW.post_status, ''), 'published');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS posts_content_rules ON posts;
CREATE TRIGGER posts_content_rules
    BEFORE INSERT ON posts
    FOR EACH ROW EXECUTE FUNCTION apply_forum_content_rules();

CREATE OR REPLACE FUNCTION apply_comment_content_rules() RETURNS trigger AS $$
DECLARE
    account_created_at timestamptz;
    today_count integer;
    suspicious boolean;
    case_id text;
BEGIN
    SELECT created_at INTO account_created_at FROM users WHERE id = NEW.author_id;
    suspicious := NEW.content ~* '(微信群|QQ群|加微信|加 ?QQ|淘宝|taobao\.com|https?://|(^|[^0-9])[0-9]{11}([^0-9]|$))';
    SELECT count(*) INTO today_count
      FROM comments
     WHERE author_id = NEW.author_id AND created_at >= date_trunc('day', now());
    IF suspicious OR (account_created_at IS NOT NULL AND account_created_at > now() - interval '24 hours' AND today_count >= 20) THEN
        case_id := md5(random()::text || clock_timestamp()::text);
        NEW.moderation_status := 'pending';
        NEW.moderation_case_id := case_id;
        INSERT INTO moderation_cases (id, target_type, target_id, source, risk_level, status)
        VALUES (case_id, 'comment', NEW.id, 'auto_rule', 'medium', 'open');
        INSERT INTO risk_events (id, user_id, event_type, severity, metadata)
        VALUES (md5(random()::text || clock_timestamp()::text), NEW.author_id, 'content_auto_review', 'medium', jsonb_build_object('target_type', 'comment'));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS comments_content_rules ON comments;
CREATE TRIGGER comments_content_rules
    BEFORE INSERT ON comments
    FOR EACH ROW EXECUTE FUNCTION apply_comment_content_rules();

CREATE TABLE IF NOT EXISTS admin_log_chain (
    id integer PRIMARY KEY CHECK (id = 1),
    last_hash text NOT NULL DEFAULT ''
);
INSERT INTO admin_log_chain (id, last_hash) VALUES (1, '') ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS admin_logs (
    id text PRIMARY KEY,
    operator_id text REFERENCES users(id),
    action text NOT NULL,
    target_type text NOT NULL,
    target_id text NOT NULL,
    reason text NOT NULL DEFAULT '',
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    previous_hash text NOT NULL DEFAULT '',
    hash text NOT NULL UNIQUE,
    request_id text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS admin_logs_created_idx
    ON admin_logs (created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS admin_logs_operator_idx
    ON admin_logs (operator_id, created_at DESC);

CREATE OR REPLACE FUNCTION prevent_admin_log_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'admin_logs are append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS admin_logs_no_update ON admin_logs;
CREATE TRIGGER admin_logs_no_update
    BEFORE UPDATE OR DELETE ON admin_logs
    FOR EACH ROW EXECUTE FUNCTION prevent_admin_log_mutation();
