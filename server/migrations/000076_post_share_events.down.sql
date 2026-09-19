-- 仅回滚事件表结构；posts.share_count 是包含历史基线的聚合值，不能安全逆向扣减。
DROP TABLE IF EXISTS post_share_events;

