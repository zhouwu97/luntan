UPDATE ranking_toys
SET rating_total_centi = rating_total_centi / 10,
    updated_at = now()
WHERE rating_count > 0;
