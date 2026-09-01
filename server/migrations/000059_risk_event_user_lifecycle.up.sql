-- 风控事件是审计快照，不应阻止账号软删除或测试/运维清理用户记录。
-- 保留 user_id 以便账号仍存在时关联主体；主体删除后置空，事件本身永久保留。
DO $$
DECLARE
    constraint_name text;
BEGIN
    SELECT conname
      INTO constraint_name
      FROM pg_constraint
     WHERE conrelid = 'risk_events'::regclass
       AND confrelid = 'users'::regclass
       AND contype = 'f'
     LIMIT 1;
    IF constraint_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE risk_events DROP CONSTRAINT %I', constraint_name);
    END IF;
END $$;

ALTER TABLE risk_events
    ADD CONSTRAINT risk_events_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

