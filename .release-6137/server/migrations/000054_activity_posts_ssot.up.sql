-- 活动业务实体统一由 activities 表承载。
-- 历史 posts.type=activity 保留用于兼容读取，但禁止新写入该类型。
-- NOT VALID 允许存量历史数据继续存在，同时约束所有后续 INSERT/UPDATE。
ALTER TABLE posts
    ADD CONSTRAINT posts_activity_type_ssot_check
    CHECK (type <> 'activity') NOT VALID;
