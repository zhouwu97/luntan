CREATE TABLE IF NOT EXISTS community_categories (
    id text PRIMARY KEY,
    parent_id text REFERENCES community_categories(id),
    name text NOT NULL,
    slug text NOT NULL,
    icon text,
    sort_order integer NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT community_categories_slug_unique UNIQUE (slug)
);

CREATE TABLE IF NOT EXISTS communities (
    id text PRIMARY KEY,
    category_id text NOT NULL REFERENCES community_categories(id),
    slug text NOT NULL,
    name text NOT NULL,
    description text NOT NULL DEFAULT '',
    avatar_media_id text,
    banner_media_id text,
    visibility text NOT NULL DEFAULT 'public',
    join_policy text NOT NULL DEFAULT 'open',
    status text NOT NULL DEFAULT 'active',
    member_count bigint NOT NULL DEFAULT 0,
    follower_count bigint NOT NULL DEFAULT 0,
    post_count bigint NOT NULL DEFAULT 0,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT communities_slug_unique UNIQUE (slug)
);
