import type { Post } from "../types/forum";
import { getPost } from "./api/forum";

const TTL_MS = 5 * 60 * 1000;
const MAX_ENTRIES = 100;
const cache = new Map<string, { savedAt: number; post: Post }>();
const inFlight = new Map<string, Promise<Post>>();
const prefetched = new Map<string, number>();
const scopeGenerations = new Map<string, number>();

function key(postId: string, accountScope?: string): string {
  return `${scopeKey(accountScope)}:${postId}`;
}

function scopeKey(accountScope?: string): string {
  return accountScope || "anon";
}

function scopeGeneration(accountScope?: string): number {
  return scopeGenerations.get(scopeKey(accountScope)) || 0;
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
    prefetched.delete(cacheKey);
    return null;
  }
  return item.post;
}

export function clearPostSnapshots(accountScope?: string): void {
  const prefix = `${accountScope || "anon"}:`;
  for (const itemKey of cache.keys()) {
    if (itemKey.startsWith(prefix)) cache.delete(itemKey);
  }
  for (const requestKey of prefetched.keys()) {
    if (requestKey.startsWith(prefix)) prefetched.delete(requestKey);
  }
  for (const requestKey of inFlight.keys()) {
    if (requestKey.startsWith(prefix)) inFlight.delete(requestKey);
  }
  const scope = scopeKey(accountScope);
  scopeGenerations.set(scope, scopeGeneration(accountScope) + 1);
}

export function prefetchPost(post: Post, accountScope?: string): Promise<Post> {
  const requestKey = key(post.id, accountScope);
  const prefetchedAt = prefetched.get(requestKey);
  if (prefetchedAt && Date.now() - prefetchedAt <= TTL_MS) {
    return Promise.resolve(getPostSnapshot(post.id, accountScope) || post);
  }
  if (prefetchedAt) prefetched.delete(requestKey);
  setPostSnapshot(post, accountScope);
  return fetchPost(post.id, accountScope);
}

export function fetchPost(postId: string, accountScope?: string): Promise<Post> {
  const requestKey = key(postId, accountScope);
  const existing = inFlight.get(requestKey);
  if (existing) return existing;

  const requestGeneration = scopeGeneration(accountScope);
  let request: Promise<Post>;
  request = getPost(postId)
    .then((post) => {
      if (scopeGeneration(accountScope) === requestGeneration) {
        setPostSnapshot(post, accountScope);
        prefetched.set(requestKey, Date.now());
      }
      return post;
    })
    .finally(() => {
      if (inFlight.get(requestKey) === request) inFlight.delete(requestKey);
    });
  inFlight.set(requestKey, request);
  return request;
}
