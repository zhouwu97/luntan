import type { Post } from "../types/forum";
import { getPost } from "./api/forum";

const TTL_MS = 5 * 60 * 1000;
const MAX_ENTRIES = 100;
const cache = new Map<string, { savedAt: number; post: Post }>();
const inFlight = new Map<string, Promise<Post>>();
const prefetched = new Set<string>();

function key(postId: string, accountScope?: string): string {
  return `${accountScope || "anon"}:${postId}`;
}

export function setPostSnapshot(post: Post, accountScope?: string): void {
  cache.set(key(post.id, accountScope), { savedAt: Date.now(), post });
  while (cache.size > MAX_ENTRIES) {
    const oldest = cache.keys().next().value as string | undefined;
    if (!oldest) break;
    cache.delete(oldest);
  }
}

export function getPostSnapshot(postId: string, accountScope?: string): Post | null {
  const cacheKey = key(postId, accountScope);
  const item = cache.get(cacheKey);
  if (!item) return null;
  if (Date.now() - item.savedAt > TTL_MS) {
    cache.delete(cacheKey);
    return null;
  }
  return item.post;
}

export function clearPostSnapshots(accountScope?: string): void {
  const prefix = `${accountScope || "anon"}:`;
  for (const itemKey of cache.keys()) {
    if (itemKey.startsWith(prefix)) cache.delete(itemKey);
  }
  for (const requestKey of prefetched) {
    if (requestKey.startsWith(prefix)) prefetched.delete(requestKey);
  }
}

export function prefetchPost(post: Post, accountScope?: string): Promise<Post> {
  const requestKey = key(post.id, accountScope);
  if (prefetched.has(requestKey)) return Promise.resolve(post);
  setPostSnapshot(post, accountScope);
  return fetchPost(post.id, accountScope);
}

export function fetchPost(postId: string, accountScope?: string): Promise<Post> {
  const requestKey = key(postId, accountScope);
  const existing = inFlight.get(requestKey);
  if (existing) return existing;

  const request = getPost(postId)
    .then((post) => {
      setPostSnapshot(post, accountScope);
      prefetched.add(requestKey);
      return post;
    })
    .finally(() => {
      inFlight.delete(requestKey);
    });
  inFlight.set(requestKey, request);
  return request;
}
