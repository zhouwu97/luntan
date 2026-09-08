DROP INDEX IF EXISTS home_recommendations_sort_idx;

ALTER TABLE home_recommendations
    DROP COLUMN is_pinned;

CREATE INDEX home_recommendations_sort_idx
    ON home_recommendations (position ASC, recommended_at DESC, post_id DESC);
