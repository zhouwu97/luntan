import type { FeedPage, Post } from "../types/forum";

export interface FeedCacheOptions {
  communityId?: string;
  sort: "recommended" | "latest" | "hot";
  latestOrder: "comment" | "post";
  hasMedia: boolean;
  topic?: string;
}

interface FeedCacheEntry {
  version: 1;
  savedAt: number;
  page: FeedPage;
}

const CACHE_PREFIX = "shengbeijiang:feed:v1:";

export function feedCacheKey(options: FeedCacheOptions): string {
  const community = options.communityId || "all";
  const topic = options.topic || "all";
  return `${CACHE_PREFIX}${community}:${options.sort}:${options.latestOrder}:${options.hasMedia ? "media" : "all"}:${topic}`;
}

function storage(): Storage | null {
  return typeof window === "undefined" ? null : window.localStorage;
}

export function readFeedCache(options: FeedCacheOptions): FeedPage | null {
  try {
    const value = storage()?.getItem(feedCacheKey(options));
    if (!value) return null;
    const entry = JSON.parse(value) as FeedCacheEntry;
    if (entry.version !== 1 || !entry.page || !Array.isArray(entry.page.items)) return null;
    return {
      items: entry.page.items as Post[],
      nextCursor: entry.page.nextCursor,
      hasMore: entry.page.hasMore === true,
    };
  } catch {
    return null;
  }
}

export function writeFeedCache(options: FeedCacheOptions, page: FeedPage): void {
  try {
    storage()?.setItem(feedCacheKey(options), JSON.stringify({ version: 1, savedAt: Date.now(), page } satisfies FeedCacheEntry));
  } catch {
    // 缓存不可用时不影响真实接口请求。
  }
}
