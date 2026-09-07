import { cache } from "react";
import { parsePost } from "./api/forum";
import type { Post } from "../types/forum";

const trimSlash = (value: string) => value.replace(/\/+$/, "");

function apiOrigin(): string {
  const configured =
    process.env.API_PROXY_TARGET?.trim() ||
    process.env.NEXT_PUBLIC_API_BASE_URL?.trim() ||
    (process.env.NODE_ENV === "development" ? "http://127.0.0.1:8080" : "https://shengbeijiang.com");
  return trimSlash(configured).replace(/\/api\/v1$/, "");
}

async function fetchPublicJson(path: string): Promise<unknown | null> {
  try {
    const response = await fetch(`${apiOrigin()}/api/v1${path}`, {
      headers: { Accept: "application/json" },
      next: { revalidate: 60 },
    });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    // SEO 数据不可用时仍让客户端壳正常接管，不能阻断帖子页面。
    return null;
  }
}

export type PublicPostResult =
  | { status: "ok"; post: Post }
  | { status: "not_found" }
  | { status: "unavailable" };

export const getPublicPost = cache(async (postId: string): Promise<PublicPostResult> => {
  try {
    const response = await fetch(
      `${apiOrigin()}/api/v1/posts/${encodeURIComponent(postId)}?include_details=1`,
      {
        headers: { Accept: "application/json" },
        next: { revalidate: 60 },
      },
    );
    if (response.status === 404 || response.status === 410) return { status: "not_found" };
    if (!response.ok) return { status: "unavailable" };
    return { status: "ok", post: parsePost(await response.json()) };
  } catch {
    // 上游故障不能伪装成内容不存在；客户端壳仍可重试恢复。
    return { status: "unavailable" };
  }
});

export const getPublicRecentPosts = cache(async (): Promise<Post[]> => {
  const payload = await fetchPublicJson("/feed/latest?limit=100&sort=latest&latest_by=comment&include_details=1");
  if (!payload || typeof payload !== "object") return [];
  const items = (payload as { items?: unknown[] }).items;
  return Array.isArray(items) ? items.map(parsePost).filter((post) => post.id) : [];
});
