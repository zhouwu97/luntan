-- 邮件投递状态机与 IP 限制。列使用 IF NOT EXISTS，支持已存在的灰度数据库幂等升级。
ALTER TABLE email_codes
    ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'created',
    ADD COLUMN IF NOT EXISTS sent_at timestamptz,
    ADD COLUMN IF NOT EXISTS verified_at timestamptz,
    ADD COLUMN IF NOT EXISTS failure_reason text NOT NULL DEFAULT '';
ALTER TABLE email_codes DROP CONSTRAINT IF EXISTS email_codes_status_check;
ALTER TABLE email_codes
    ADD CONSTRAINT email_codes_status_check CHECK (status IN ('created', 'sending', 'sent', 'delivery_failed', 'verified', 'expired'));
UPDATE email_codes SET status = CASE WHEN consumed_at IS NOT NULL THEN 'verified' ELSE 'sent' END WHERE status = 'created';
CREATE INDEX IF NOT EXISTS email_codes_status_lookup_idx
    ON email_codes (lower(email), purpose, status, created_at DESC);

CREATE TABLE IF NOT EXISTS ip_restrictions (
    id text PRIMARY KEY,
    ip_cidr cidr NOT NULL,
    restriction_type text NOT NULL DEFAULT 'access',
    reason text NOT NULL DEFAULT '',
    starts_at timestamptz NOT NULL DEFAULT now(),
    ends_at timestamptz,
    revoked_at timestamptz,
    created_by text REFERENCES users(id),
    revoked_by text REFERENCES users(id),
    operator_id text REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ip_restrictions
    ADD COLUMN IF NOT EXISTS restriction_type text NOT NULL DEFAULT 'access',
    ADD COLUMN IF NOT EXISTS created_by text REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS revoked_by text REFERENCES users(id);
UPDATE ip_restrictions SET created_by = operator_id WHERE created_by IS NULL AND operator_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ip_restrictions_active_idx
    ON ip_restrictions (starts_at, ends_at) WHERE revoked_at IS NULL;

ALTER TABLE admin_logs ADD COLUMN IF NOT EXISTS ip_address text NOT NULL DEFAULT '';

INSERT INTO permissions (id, name)
VALUES ('perm-admin-role-manage', 'admin.role.manage')
ON CONFLICT (name) DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'role-super-admin', id FROM permissions WHERE name = 'admin.role.manage'
ON CONFLICT DO NOTHING;
