-- 全站公开 Feed 不带 community_id 时使用该部分索引，避免扫描草稿、隐藏和软删除帖子。
CREATE INDEX IF NOT EXISTS posts_public_feed_idx
    ON posts (published_at DESC, id DESC)
    WHERE publication_status = 'published'
      AND moderation_status = 'normal'
      AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS posts_public_hot_idx
    ON posts (comment_count DESC, like_count DESC, published_at DESC, id DESC)
    WHERE publication_status = 'published'
      AND moderation_status = 'normal'
      AND deleted_at IS NULL;
