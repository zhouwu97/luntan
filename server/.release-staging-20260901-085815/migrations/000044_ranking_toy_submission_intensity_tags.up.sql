-- 投稿表单对齐源站：增加刺激度类型（写入 ranking_toys.segments 词汇表）
-- 与展示标签（≤3 个，每个 ≤4 字，通过后复制进 ranking_toys.tags）。
ALTER TABLE ranking_toy_submissions
    ADD COLUMN IF NOT EXISTS intensity text NOT NULL DEFAULT ''
        CHECK (intensity IN ('', 'beginner', 'advanced', 'high_stim', 'juice')),
    ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT ARRAY[]::text[];
