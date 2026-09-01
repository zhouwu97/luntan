-- 活动把“是否公开”和“时间阶段”拆成两个概念。
ALTER TABLE activities
    ADD COLUMN IF NOT EXISTS publication_status text;

-- 迁移历史 status：draft/offline 是发布状态，其余旧值均表示已发布。
UPDATE activities
SET publication_status = CASE
    WHEN status IN ('draft', 'offline') THEN status
    ELSE 'published'
END
WHERE publication_status IS NULL OR btrim(publication_status) = '';

ALTER TABLE activities
    ALTER COLUMN publication_status SET DEFAULT 'draft',
    ALTER COLUMN publication_status SET NOT NULL;

ALTER TABLE activities DROP CONSTRAINT IF EXISTS activities_publication_status_check;
ALTER TABLE activities
    ADD CONSTRAINT activities_publication_status_check
    CHECK (publication_status IN ('draft', 'published', 'offline'));

CREATE INDEX IF NOT EXISTS activities_publication_status_idx
    ON activities (publication_status, published_at DESC, id DESC)
    WHERE deleted_at IS NULL;
