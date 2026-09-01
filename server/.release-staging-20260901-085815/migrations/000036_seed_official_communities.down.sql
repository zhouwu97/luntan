-- 回滚 000036：仅清理本次 migration 引入的官方基础数据。
-- 已产生内容的社区由外键/业务逻辑保护，这里不做级联删除。
DELETE FROM communities WHERE id IN ('community-unboxing', 'community-campus', 'community-daily');
DELETE FROM community_categories WHERE id IN ('category-digital', 'category-campus', 'category-life');
