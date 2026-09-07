SELECT count(*) AS pending_backfill
FROM media_assets ma
WHERE ma.status = 'ready'
  AND ma.deleted_at IS NULL
  AND ma.mime_type LIKE 'image/%'
  AND (
    (ma.mime_type = 'image/gif' AND NOT EXISTS (
      SELECT 1
      FROM media_variants mv
      WHERE mv.media_id = ma.id AND mv.variant = 'source' AND mv.status = 'ready'
    ))
    OR
    (ma.mime_type <> 'image/gif' AND NOT (
      EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'original' AND mv.status = 'ready')
      AND EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'detail' AND mv.status = 'ready')
      AND EXISTS (SELECT 1 FROM media_variants mv WHERE mv.media_id = ma.id AND mv.variant = 'thumb' AND mv.status = 'ready')
    ))
  );
