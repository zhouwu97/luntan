import { cache } from "react";
import { parseActivity } from "./api/forum";
import type { ActivityItem } from "../types/forum";

const trimSlash = (value: string) => value.replace(/\/+$/, "");

function apiOrigin(): string {
  const configured =
    process.env.API_PROXY_TARGET?.trim() ||
    process.env.NEXT_PUBLIC_API_BASE_URL?.trim() ||
    (process.env.NODE_ENV === "development" ? "http://127.0.0.1:8080" : "https://shengbeijiang.com");
  return trimSlash(configured).replace(/\/api\/v1$/, "");
}

export type PublicActivityResult =
  | { status: "ok"; activity: ActivityItem }
  | { status: "not_found" }
  | { status: "unavailable" };

export const getPublicActivity = cache(async (activityID: string): Promise<PublicActivityResult> => {
  try {
    const response = await fetch(`${apiOrigin()}/api/v1/activities/${encodeURIComponent(activityID)}`, {
      headers: { Accept: "application/json" },
      // 活动下线/删除必须立即生效，不能让 SSR 数据缓存继续暴露旧内容。
      cache: "no-store",
    });
    if (response.status === 404 || response.status === 410) return { status: "not_found" };
    if (!response.ok) return { status: "unavailable" };
    const activity = parseActivity(await response.json());
    return activity.id ? { status: "ok", activity } : { status: "not_found" };
  } catch {
    return { status: "unavailable" };
  }
});
