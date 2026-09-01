CREATE TABLE IF NOT EXISTS bookmark_folders (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    name text NOT NULL,
    is_default boolean NOT NULL DEFAULT false,
    sort_order integer NOT NULL DEFAULT 0,
    idempotency_key text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS bookmark_folders_default_user_idx
    ON bookmark_folders (user_id)
    WHERE is_default = true;

CREATE UNIQUE INDEX IF NOT EXISTS bookmark_folders_user_name_idx
    ON bookmark_folders (user_id, lower(name));

CREATE UNIQUE INDEX IF NOT EXISTS bookmark_folders_user_idempotency_idx
    ON bookmark_folders (user_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS bookmark_folders_user_sort_idx
    ON bookmark_folders (user_id, sort_order ASC, created_at ASC, id ASC);

CREATE TABLE IF NOT EXISTS bookmark_folder_items (
    folder_id text NOT NULL REFERENCES bookmark_folders(id) ON DELETE CASCADE,
    post_id text NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (folder_id, post_id)
);

CREATE INDEX IF NOT EXISTS bookmark_folder_items_post_idx
    ON bookmark_folder_items (post_id, created_at DESC);

CREATE INDEX IF NOT EXISTS bookmark_folder_items_folder_created_idx
    ON bookmark_folder_items (folder_id, created_at DESC, post_id DESC);

-- 把旧收藏事实迁入每位用户唯一的默认收藏夹，保证升级不丢收藏。
INSERT INTO bookmark_folders (id, user_id, name, is_default, sort_order)
SELECT 'folder_default_' || md5(b.user_id), b.user_id, '默认收藏夹', true, 0
FROM bookmarks b
GROUP BY b.user_id
ON CONFLICT (user_id) WHERE is_default = true DO NOTHING;

INSERT INTO bookmark_folder_items (folder_id, post_id, created_at)
SELECT f.id, b.post_id, b.created_at
FROM bookmarks b
JOIN bookmark_folders f ON f.user_id = b.user_id AND f.is_default = true
ON CONFLICT (folder_id, post_id) DO NOTHING;
