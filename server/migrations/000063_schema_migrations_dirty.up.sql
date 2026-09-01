-- 迁移状态需要显式记录 dirty，供发布验收判断是否存在半完成迁移。
ALTER TABLE schema_migrations
    ADD COLUMN IF NOT EXISTS dirty boolean NOT NULL DEFAULT false;
