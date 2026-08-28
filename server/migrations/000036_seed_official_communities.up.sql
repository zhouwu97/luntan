-- 官方分区与社区是产品的基础数据：Flutter 端发布页固定展示「大型拆箱 / 酱紫社区 /
-- 杂鱼日常」三个分区，createPost 也强依赖 active 社区。此前它们只存在于 dev seed
-- （server/seeds/dev/001_forum.sql，明确禁止在生产执行），导致全新生产库部署后
-- 社区列表为空、任何发帖都被 COMMUNITY_NOT_FOUND 拒绝。
-- 这里以幂等方式把基础数据纳入 schema migration，全新环境开箱可发帖。
INSERT INTO community_categories (id, name, slug, sort_order)
VALUES
    ('category-digital', '数码', 'digital', 1),
    ('category-campus', '校园', 'campus', 2),
    ('category-life', '生活', 'life', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO communities (id, category_id, slug, name, description, sort_order, status)
VALUES
    ('community-unboxing', 'category-digital', 'unboxing', '大型拆箱', '分享设备、桌搭和真实使用体验', 1, 'active'),
    ('community-campus', 'category-campus', 'campus', '酱紫社区', '校园讨论、问答和同学交流', 2, 'active'),
    ('community-daily', 'category-life', 'daily', '杂鱼日常', '记录校园生活与身边的小事', 3, 'active')
ON CONFLICT (id) DO NOTHING;
