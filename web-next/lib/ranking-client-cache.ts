import type { RankingToy } from "../types/forum";

const CACHE_PREFIX = "ranking:toy:";

export function writeRankingToyCache(item: RankingToy): void {
  if (typeof window === "undefined" || !item.id) return;
  try {
    window.sessionStorage.setItem(`${CACHE_PREFIX}${item.id}`, JSON.stringify(item));
  } catch {
    // 存储空间不足或隐私模式禁用时不影响正常网络请求。
  }
}

export function readRankingToyCache(id: string): RankingToy | null {
  if (typeof window === "undefined" || !id) return null;
  try {
    const raw = window.sessionStorage.getItem(`${CACHE_PREFIX}${id}`);
    if (!raw) return null;
    const item = JSON.parse(raw) as Partial<RankingToy>;
    return item && typeof item === "object" && item.id === id && typeof item.name === "string"
      ? item as RankingToy
      : null;
  } catch {
    return null;
  }
}
