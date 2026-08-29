-- 导入器按各视图的源站顺序写 ranking_toys.rank；停用的历史种子与被
-- 源站下架的商品不再参与排序，rank 上的唯一约束会让名次重排失败，
-- 因此移除（默认榜单只依赖 rank 的排序，不依赖唯一性）。
ALTER TABLE ranking_toys DROP CONSTRAINT IF EXISTS ranking_toys_rank_key;
