CREATE SEQUENCE IF NOT EXISTS user_public_id_seq
    AS bigint
    MINVALUE 10000
    START WITH 10000;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS public_id bigint;

-- 存量正式账号按注册时间稳定回填，游客仅在绑定邮箱成为正式账号时分配。
WITH ranked AS (
    SELECT id, 9999 + row_number() OVER (ORDER BY created_at ASC, id ASC) AS public_id
    FROM users
    WHERE account_type <> 'guest'
      AND public_id IS NULL
)
UPDATE users AS target
SET public_id = ranked.public_id
FROM ranked
WHERE target.id = ranked.id;

CREATE UNIQUE INDEX IF NOT EXISTS users_public_id_unique_idx
    ON users (public_id)
    WHERE public_id IS NOT NULL;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_public_id_range_check;
ALTER TABLE users
    ADD CONSTRAINT users_public_id_range_check
    CHECK (public_id IS NULL OR public_id >= 10000);

SELECT setval(
    'user_public_id_seq',
    GREATEST(COALESCE((SELECT max(public_id) FROM users), 9999) + 1, 10000),
    false
);

CREATE OR REPLACE FUNCTION assign_user_public_id()
RETURNS trigger AS $$
BEGIN
    IF NEW.account_type = 'guest' THEN
        NEW.public_id := NULL;
    ELSIF NEW.public_id IS NULL THEN
        NEW.public_id := nextval('user_public_id_seq');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS users_assign_public_id ON users;
CREATE TRIGGER users_assign_public_id
BEFORE INSERT OR UPDATE OF account_type ON users
FOR EACH ROW
EXECUTE FUNCTION assign_user_public_id();
