-- 帖子评论楼层视图需要独立统计点踩数；点赞数已有 like_count。
ALTER TABLE comments
    ADD COLUMN IF NOT EXISTS dislike_count bigint NOT NULL DEFAULT 0 CHECK (dislike_count >= 0);
