-- 榜单玩具开放投稿：登录用户提交新玩具，仅超级管理员可审核；
-- 通过后写入 ranking_toys 综合热榜末尾，不进入 ranking_toy_rankings。
CREATE TABLE IF NOT EXISTS ranking_toy_submissions (
    id text PRIMARY KEY,
    submitter_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name text NOT NULL,
    category text NOT NULL CHECK (category IN ('cup', 'small_hip', 'large_hip', 'half_body', 'lubricant')),
    merchant text NOT NULL DEFAULT '',
    release_year integer CHECK (release_year IS NULL OR (release_year >= 1970 AND release_year <= 2100)),
    description text NOT NULL DEFAULT '',
    cover_media_id text REFERENCES media_assets(id),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    review_note text NOT NULL DEFAULT '',
    reviewed_by text REFERENCES users(id),
    reviewed_at timestamptz,
    toy_id text REFERENCES ranking_toys(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ranking_toy_submissions_status_created_idx
    ON ranking_toy_submissions (status, created_at DESC);

CREATE INDEX IF NOT EXISTS ranking_toy_submissions_submitter_idx
    ON ranking_toy_submissions (submitter_id, status);
