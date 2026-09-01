CREATE TABLE IF NOT EXISTS store_products (
    id text PRIMARY KEY,
    name text NOT NULL,
    description text NOT NULL DEFAULT '',
    emoji text NOT NULL DEFAULT '🎁',
    points bigint NOT NULL CHECK (points > 0),
    color integer NOT NULL DEFAULT 0,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS store_orders (
    id text PRIMARY KEY,
    user_id text NOT NULL REFERENCES users(id),
    product_id text NOT NULL REFERENCES store_products(id),
    points bigint NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS store_orders_user_created_idx ON store_orders (user_id, created_at DESC, id DESC);

INSERT INTO store_products (id, name, description, emoji, points, color)
VALUES
    ('badge', '论坛纪念徽章', '论坛限定周边', '🏅', 600, 16766842),
    ('keychain', '校园钥匙扣', '限量周边', '🔑', 900, 11197689),
    ('stickers', '主题贴纸包', '社区纪念', '✨', 350, 16758736),
    ('tote', '校园帆布袋', '生活周边', '👜', 1800, 12052693)
ON CONFLICT (id) DO NOTHING;
