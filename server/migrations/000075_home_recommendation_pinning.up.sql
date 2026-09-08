ALTER TABLE home_recommendations
    ADD COLUMN is_pinned boolean NOT NULL DEFAULT false;

DROP INDEX IF EXISTS home_recommendations_sort_idx;
CREATE INDEX home_recommendations_sort_idx
    ON home_recommendations (is_pinned DESC, position ASC, recommended_at DESC, post_id DESC);
