-- 审核处理在生成变体期间不持有行锁；revision 用于拒绝处理开始后已过期的提交。
ALTER TABLE media_assets
    ADD COLUMN IF NOT EXISTS moderation_revision bigint NOT NULL DEFAULT 0;
