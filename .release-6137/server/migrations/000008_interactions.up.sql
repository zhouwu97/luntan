CREATE TABLE IF NOT EXISTS post_reactions (
    post_id text NOT NULL REFERENCES posts(id),
    user_id text NOT NULL REFERENCES users(id),
    reaction_type text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id, reaction_type)
);

CREATE INDEX IF NOT EXISTS post_reactions_user_idx ON post_reactions (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS comment_reactions (
    comment_id text NOT NULL REFERENCES comments(id),
    user_id text NOT NULL REFERENCES users(id),
    reaction_type text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (comment_id, user_id, reaction_type)
);

CREATE INDEX IF NOT EXISTS comment_reactions_user_idx ON comment_reactions (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS bookmarks (
    post_id text NOT NULL REFERENCES posts(id),
    user_id text NOT NULL REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, user_id)
);

CREATE INDEX IF NOT EXISTS bookmarks_user_created_idx ON bookmarks (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS user_follows (
    follower_id text NOT NULL REFERENCES users(id),
    followee_id text NOT NULL REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id),
    CONSTRAINT user_follows_no_self CHECK (follower_id <> followee_id)
);

CREATE INDEX IF NOT EXISTS user_follows_followee_idx ON user_follows (followee_id, created_at DESC);

CREATE TABLE IF NOT EXISTS community_follows (
    user_id text NOT NULL REFERENCES users(id),
    community_id text NOT NULL REFERENCES communities(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, community_id)
);

CREATE INDEX IF NOT EXISTS community_follows_community_idx ON community_follows (community_id, created_at DESC);

CREATE TABLE IF NOT EXISTS community_members (
    community_id text NOT NULL REFERENCES communities(id),
    user_id text NOT NULL REFERENCES users(id),
    role text NOT NULL DEFAULT 'member',
    status text NOT NULL DEFAULT 'active',
    joined_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (community_id, user_id)
);

CREATE INDEX IF NOT EXISTS community_members_user_idx ON community_members (user_id, updated_at DESC);
