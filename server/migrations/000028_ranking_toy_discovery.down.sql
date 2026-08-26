DROP INDEX IF EXISTS ranking_toys_segments_idx;
DROP INDEX IF EXISTS ranking_toys_category_idx;

ALTER TABLE ranking_toys
    DROP COLUMN IF EXISTS segments,
    DROP COLUMN IF EXISTS category;
