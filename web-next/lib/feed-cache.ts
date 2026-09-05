import type { FeedPage, Post } from "../types/forum";

export interface FeedCacheOptions {
  communityId?: string;
  sort: "recommended" | "latest" | "hot";
  latestOrder: "comment" | "post";
  hasMedia: boolean;
  topic?: string;
  accountScope?: string;
}

interface FeedCacheEntry {
  version: 2;
  savedAt: number;
  lastAccessedAt: number;
  page: FeedPage;
}

const CACHE_PREFIX = "shengbeijiang:feed:v2:";
const SOFT_TTL_MS = 60 * 1000;
const MAX_AGE_MS = 30 * 60 * 1000;
const MAX_ENTRIES = 20;
const MAX_BYTES = 4 * 1024 * 1024;
const memoryCache = new Map<string, FeedCacheEntry>();

export function feedCacheKey(options: FeedCacheOptions): string {
  const account = encodeURIComponent(options.accountScope || "anon");
  const query = [options.communityId || "all", options.sort, options.latestOrder,
    options.hasMedia ? "media" : "all", options.topic || "all"]
    .map(encodeURIComponent).join(":");
  return `${CACHE_PREFIX}${account}:${query}`;
}

function storage(): Storage | null {
  return typeof window === "undefined" ? null : window.localStorage;
}

function byteLength(value: string): number {
  return new TextEncoder().encode(value).byteLength;
}

function entries(): Array<{ key: string; raw: string; entry: FeedCacheEntry }> {
  const store = storage();
  if (!store) return [];
  const result: Array<{ key: string; raw: string; entry: FeedCacheEntry }> = [];
  for (let index = 0; index < store.length; index += 1) {
    const key = store.key(index);
    if (!key?.startsWith(CACHE_PREFIX)) continue;
    const raw = store.getItem(key);
    if (!raw) continue;
    try {
      const entry = JSON.parse(raw) as FeedCacheEntry;
      if (entry.version === 2 && entry.page && Array.isArray(entry.page.items)) {
        result.push({ key, raw, entry });
      } else {
        store.removeItem(key);
        memoryCache.delete(key);
      }
    } catch {
      store.removeItem(key);
      memoryCache.delete(key);
    }
  }
  return result;
}

function trimMemoryCache(): void {
  const candidates = [...memoryCache.entries()]
    .sort(([, left], [, right]) => left.lastAccessedAt - right.lastAccessedAt);
  let total = candidates.reduce((sum, [, entry]) => sum + byteLength(JSON.stringify(entry)), 0);
  while (candidates.length > MAX_ENTRIES || total > MAX_BYTES) {
    const removed = candidates.shift();
    if (!removed) break;
    memoryCache.delete(removed[0]);
    total -= byteLength(JSON.stringify(removed[1]));
  }
}

export function readFeedCache(options: FeedCacheOptions): FeedPage | null {
  return readFeedCacheSnapshot(options)?.page || null;
}

export interface FeedCacheSnapshot {
  page: FeedPage;
  ageMs: number;
  isFresh: boolean;
}

export function readFeedCacheSnapshot(options: FeedCacheOptions): FeedCacheSnapshot | null {
  try {
    const store = storage();
    const key = feedCacheKey(options);
    const raw = store?.getItem(key);
    const entry = memoryCache.get(key) || (raw ? JSON.parse(raw) as FeedCacheEntry : null);
    if (!entry) return null;
    if (entry.version !== 2 || !entry.page || !Array.isArray(entry.page.items)) {
      store?.removeItem(key);
      memoryCache.delete(key);
      return null;
    }
    if (Date.now() - entry.savedAt > MAX_AGE_MS) {
      store?.removeItem(key);
      memoryCache.delete(key);
      return null;
    }
    const now = Date.now();
    const touchedEntry = { ...entry, lastAccessedAt: now } satisfies FeedCacheEntry;
    memoryCache.set(key, touchedEntry);
    store?.setItem(key, JSON.stringify(touchedEntry));
    return {
      ageMs: Math.max(0, now - entry.savedAt),
      isFresh: options.sort !== "recommended" && now - entry.savedAt <= SOFT_TTL_MS,
      page: {
      items: entry.page.items as Post[],
      nextCursor: entry.page.nextCursor,
      hasMore: entry.page.hasMore === true,
      },
    };
  } catch {
    return null;
  }
}

export function writeFeedCache(options: FeedCacheOptions, page: FeedPage): void {
  try {
    const store = storage();
    if (!store) return;
    const now = Date.now();
    const key = feedCacheKey(options);
    const raw = JSON.stringify({ version: 2, savedAt: now, lastAccessedAt: now, page } satisfies FeedCacheEntry);
    memoryCache.set(key, JSON.parse(raw) as FeedCacheEntry);
    store.setItem(key, raw);
    const candidates = entries().sort((left, right) => left.entry.lastAccessedAt - right.entry.lastAccessedAt);
    let total = candidates.reduce((sum, item) => sum + byteLength(item.raw), 0);
    while (candidates.length > MAX_ENTRIES || total > MAX_BYTES) {
      const removed = candidates.shift();
      if (!removed) break;
      store.removeItem(removed.key);
      memoryCache.delete(removed.key);
      total -= byteLength(removed.raw);
    }
    trimMemoryCache();
  } catch {
    // localStorage 不可用或空间不足时不影响真实接口请求。
  }
}

export function clearFeedCache(accountScope?: string): void {
  const store = storage();
  const prefix = accountScope ? `${CACHE_PREFIX}${encodeURIComponent(accountScope)}:` : CACHE_PREFIX;
  if (store) {
    for (let index = store.length - 1; index >= 0; index -= 1) {
      const key = store.key(index);
      if (key?.startsWith(prefix)) {
        store.removeItem(key);
        memoryCache.delete(key);
      }
    }
  }
  for (const key of memoryCache.keys()) {
    if (key.startsWith(prefix)) memoryCache.delete(key);
  }
}
