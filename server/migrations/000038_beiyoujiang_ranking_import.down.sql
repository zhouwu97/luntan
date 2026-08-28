ALTER TABLE ranking_toy_rating_distribution
    DROP COLUMN IF EXISTS source_rating_count;

DROP INDEX IF EXISTS ranking_toy_comment_media_comment_order_idx;
DROP TABLE IF EXISTS ranking_toy_comment_media;

DROP INDEX IF EXISTS ranking_toy_comments_source_identity_idx;
ALTER TABLE ranking_toy_comments
    DROP COLUMN IF EXISTS source_comment_id,
    DROP COLUMN IF EXISTS source_provider;

DROP INDEX IF EXISTS ranking_toy_rankings_view_order_idx;
DROP TABLE IF EXISTS ranking_toy_rankings;

DROP INDEX IF EXISTS ranking_toys_source_provider_toy_id_idx;
ALTER TABLE ranking_toys
    DROP COLUMN IF EXISTS source_url,
    DROP COLUMN IF EXISTS coupon_url,
    DROP COLUMN IF EXISTS hero_media_id,
    DROP COLUMN IF EXISTS cover_media_id,
    DROP COLUMN IF EXISTS source_rating_count,
    DROP COLUMN IF EXISTS source_rating_total_centi,
    DROP COLUMN IF EXISTS source_want_count,
    DROP COLUMN IF EXISTS source_updated_at,
    DROP COLUMN IF EXISTS source_toy_id,
    DROP COLUMN IF EXISTS source_provider;
