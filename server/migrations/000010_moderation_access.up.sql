CREATE TABLE IF NOT EXISTS reports (
    id text PRIMARY KEY,
    reporter_id text NOT NULL REFERENCES users(id),
    target_type text NOT NULL,
    target_id text NOT NULL,
    reason_code text NOT NULL,
    description text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS reports_open_reporter_target_idx ON reports (reporter_id, target_type, target_id) WHERE status IN ('pending', 'reviewing');
CREATE INDEX IF NOT EXISTS reports_status_created_idx ON reports (status, created_at ASC, id ASC);

CREATE TABLE IF NOT EXISTS moderation_cases (
    id text PRIMARY KEY,
    target_type text NOT NULL,
    target_id text NOT NULL,
    source text NOT NULL,
    risk_level text NOT NULL DEFAULT 'low',
    status text NOT NULL DEFAULT 'open',
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz
);

CREATE INDEX IF NOT EXISTS moderation_cases_status_created_idx ON moderation_cases (status, created_at ASC, id ASC);
CREATE INDEX IF NOT EXISTS moderation_cases_target_idx ON moderation_cases (target_type, target_id, created_at DESC);

CREATE TABLE IF NOT EXISTS moderation_actions (
    id text PRIMARY KEY,
    case_id text NOT NULL REFERENCES moderation_cases(id),
    operator_id text NOT NULL REFERENCES users(id),
    action text NOT NULL,
    reason text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS roles (
    id text PRIMARY KEY,
    name text NOT NULL UNIQUE,
    scope text NOT NULL DEFAULT 'platform',
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS permissions (
    id text PRIMARY KEY,
    name text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id text NOT NULL REFERENCES roles(id),
    permission_id text NOT NULL REFERENCES permissions(id),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS user_roles (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    role_id text NOT NULL REFERENCES roles(id),
    community_id text REFERENCES communities(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_roles_permission_scope_idx ON user_roles (user_id, community_id);
CREATE UNIQUE INDEX IF NOT EXISTS user_roles_unique_scope_idx ON user_roles (user_id, role_id, COALESCE(community_id, ''));

INSERT INTO roles (id, name, scope) VALUES
    ('role-user', 'user', 'platform'),
    ('role-community-moderator', 'community_moderator', 'community'),
    ('role-community-owner', 'community_owner', 'community'),
    ('role-platform-moderator', 'platform_moderator', 'platform'),
    ('role-platform-admin', 'platform_admin', 'platform'),
    ('role-super-admin', 'super_admin', 'platform')
ON CONFLICT (id) DO NOTHING;

INSERT INTO permissions (id, name) VALUES
    ('perm-post-delete-own', 'post.delete.own'),
    ('perm-post-hide-community', 'post.hide.community'),
    ('perm-comment-delete-own', 'comment.delete.own'),
    ('perm-comment-hide-community', 'comment.hide.community'),
    ('perm-member-mute', 'member.mute'),
    ('perm-member-ban', 'member.ban'),
    ('perm-moderation-action', 'moderation.action'),
    ('perm-audit-read', 'audit.read'),
    ('perm-report-review', 'report.review'),
    ('perm-community-edit', 'community.edit'),
    ('perm-user-ban-global', 'user.ban.global')
ON CONFLICT (id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT 'role-platform-moderator', id FROM permissions WHERE name IN ('moderation.action', 'report.review', 'audit.read')
ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'role-platform-admin', id FROM permissions
ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'role-super-admin', id FROM permissions
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS audit_logs (
    id text PRIMARY KEY,
    operator_id text REFERENCES users(id),
    action text NOT NULL,
    target_type text NOT NULL,
    target_id text NOT NULL,
    reason text NOT NULL DEFAULT '',
    before_data jsonb,
    after_data jsonb,
    request_id text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS audit_logs_target_created_idx ON audit_logs (target_type, target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_logs_operator_created_idx ON audit_logs (operator_id, created_at DESC);

ALTER TABLE posts ADD COLUMN IF NOT EXISTS deleted_by text REFERENCES users(id);
ALTER TABLE posts ADD COLUMN IF NOT EXISTS delete_reason text NOT NULL DEFAULT '';
ALTER TABLE posts ADD COLUMN IF NOT EXISTS moderation_case_id text REFERENCES moderation_cases(id);
ALTER TABLE posts ADD COLUMN IF NOT EXISTS visibility_reason text NOT NULL DEFAULT '';
ALTER TABLE comments ADD COLUMN IF NOT EXISTS deleted_by text REFERENCES users(id);
ALTER TABLE comments ADD COLUMN IF NOT EXISTS delete_reason text NOT NULL DEFAULT '';
ALTER TABLE comments ADD COLUMN IF NOT EXISTS moderation_case_id text REFERENCES moderation_cases(id);
ALTER TABLE comments ADD COLUMN IF NOT EXISTS visibility_reason text NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS blocks (
    blocker_id text NOT NULL REFERENCES users(id),
    blocked_id text NOT NULL REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT blocks_no_self CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS blocks_blocked_idx ON blocks (blocked_id, created_at DESC);
