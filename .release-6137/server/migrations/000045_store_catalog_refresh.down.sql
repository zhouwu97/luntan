UPDATE store_products SET points = 600, updated_at = now() WHERE id = 'badge';

UPDATE store_products SET active = false, updated_at = now()
WHERE id IN ('standee', 'cup-blind-box');

UPDATE store_products SET active = true, updated_at = now()
WHERE id IN ('stickers', 'keychain', 'tote')
  AND active = false;
