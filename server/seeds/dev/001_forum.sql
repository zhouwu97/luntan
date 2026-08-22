-- 开发环境 seed 与 schema migration 分离；生产环境不得自动执行本文件。
INSERT INTO users (id, username, status)
VALUES ('user-1', 'xiaoli', 'active')
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_profiles (user_id, nickname, level)
VALUES ('user-1', '小理不理', 8)
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO community_categories (id, name, slug, sort_order)
VALUES
    ('category-digital', '数码', 'digital', 1),
    ('category-campus', '校园', 'campus', 2),
    ('category-life', '生活', 'life', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO communities (id, category_id, slug, name, description, sort_order)
VALUES
    ('community-unboxing', 'category-digital', 'unboxing', '大型拆箱', '分享设备、桌搭和真实使用体验', 1),
    ('community-campus', 'category-campus', 'campus', '酱紫社区', '校园讨论、问答和同学交流', 2),
    ('community-daily', 'category-life', 'daily', '杂鱼日常', '记录校园生活与身边的小事', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO posts (id, author_id, community_id, type, publication_status, moderation_status, title, content, published_at)
VALUES ('seed-post-1', 'user-1', 'community-unboxing', 'normal', 'published', 'normal', '开发环境示例帖子', '这是开发环境 seed 数据，不用于生产。', now())
ON CONFLICT (id) DO NOTHING;
