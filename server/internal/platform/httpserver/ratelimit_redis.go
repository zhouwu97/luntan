package httpserver

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

var redisRateLimitScript = redis.NewScript(`
local current = redis.call("INCR", KEYS[1])
if current == 1 then
  redis.call("PEXPIRE", KEYS[1], ARGV[1])
end
return current
`)

// RedisRateLimitStore 为多实例 API 提供原子、共享且自动过期的限流计数。
type RedisRateLimitStore struct {
	client *redis.Client
}

func NewRedisRateLimitStore(rawURL string) (*RedisRateLimitStore, error) {
	options, err := redis.ParseURL(rawURL)
	if err != nil {
		return nil, fmt.Errorf("parse REDIS_URL: %w", err)
	}
	client := redis.NewClient(options)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("connect redis: %w", err)
	}
	return &RedisRateLimitStore{client: client}, nil
}

func (s *RedisRateLimitStore) Allow(ctx context.Context, key string, limit int, window time.Duration, _ time.Time) (bool, error) {
	count, err := redisRateLimitScript.Run(ctx, s.client, []string{key}, window.Milliseconds()).Int64()
	if err != nil {
		return false, err
	}
	return count <= int64(limit), nil
}

func (s *RedisRateLimitStore) Close() error { return s.client.Close() }
