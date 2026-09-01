ALTER TABLE ranking_toys
    ADD COLUMN IF NOT EXISTS category text NOT NULL DEFAULT 'cup',
    ADD COLUMN IF NOT EXISTS segments text[] NOT NULL DEFAULT ARRAY[]::text[];

CREATE INDEX IF NOT EXISTS ranking_toys_category_idx ON ranking_toys (category);
CREATE INDEX IF NOT EXISTS ranking_toys_segments_idx ON ranking_toys USING gin (segments);

-- 更新现有20款种子的分类与榜单标签
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['beginner'] WHERE id = 'toy-butter-2';
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['beginner'] WHERE id = 'toy-yingchuan-2';
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['advanced'] WHERE id = 'toy-yutou';
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['advanced'] WHERE id = 'toy-yuanqi';
UPDATE ranking_toys SET category = 'half_body', segments = ARRAY['beginner', 'advanced'] WHERE id = 'toy-shendai';
UPDATE ranking_toys SET category = 'large_hip', segments = ARRAY['beginner'] WHERE id = 'toy-hoshino-2';
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['advanced'] WHERE id = 'toy-nanako-2';
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['beginner'] WHERE id = 'toy-aili';
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['beginner'] WHERE id = 'toy-liulizi';
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['juice', 'high_stim'] WHERE id = 'toy-kekelang';
UPDATE ranking_toys SET category = 'small_hip', segments = ARRAY['advanced'] WHERE id = 'toy-piaogui-2';
UPDATE ranking_toys SET category = 'small_hip', segments = ARRAY['high_stim'] WHERE id = 'toy-hu-hu-zi';
UPDATE ranking_toys SET category = 'large_hip', segments = ARRAY['high_stim', 'juice'] WHERE id = 'toy-huanru';
UPDATE ranking_toys SET category = 'large_hip', segments = ARRAY['high_stim', 'juice'] WHERE id = 'toy-xiaogui';
UPDATE ranking_toys SET category = 'large_hip', segments = ARRAY['high_stim'] WHERE id = 'toy-chiyuan';
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['high_stim'] WHERE id = 'toy-tun-niang';
UPDATE ranking_toys SET category = 'half_body', segments = ARRAY['high_stim'] WHERE id = 'toy-baishi-2';
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['beginner'] WHERE id = 'toy-gonglai';
UPDATE ranking_toys SET category = 'cup', segments = ARRAY['advanced'] WHERE id = 'toy-qianmei';
UPDATE ranking_toys SET category = 'lubricant', segments = ARRAY['beginner'] WHERE id = 'toy-shuiye-2';
