CREATE TABLE IF NOT EXISTS comment_idempotency_keys (
    user_id text NOT NULL REFERENCES users(id),
    idempotency_key text NOT NULL,
    -- 先占位再写 comments，约束延迟到事务提交时检查，支持并发请求共享同一个 key。
    comment_id text NOT NULL REFERENCES comments(id) DEFERRABLE INITIALLY DEFERRED,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, idempotency_key)
);

CREATE UNIQUE INDEX IF NOT EXISTS comment_idempotency_keys_comment_idx
    ON comment_idempotency_keys (comment_id);

CREATE INDEX IF NOT EXISTS comment_idempotency_keys_created_idx
    ON comment_idempotency_keys (created_at);
