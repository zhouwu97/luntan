-- 评论图片附件表
CREATE TABLE IF NOT EXISTS comment_media (
    comment_id text NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    media_id text NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (comment_id, media_id)
);

CREATE INDEX IF NOT EXISTS idx_comment_media_comment_id ON comment_media (comment_id, sort_order ASC);

-- 评论大表情/贴纸 ID 字段
ALTER TABLE comments ADD COLUMN IF NOT EXISTS sticker_id text;
