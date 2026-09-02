import type { Community } from "../types/forum";

export const HOME_COMMUNITY_IDS = [
  "community-unboxing",
  "community-campus",
  "community-daily",
] as const;

const HOME_COMMUNITY_NAMES = new Set(["大型拆箱", "酱紫社区", "杂鱼日常"]);
const HOME_COMMUNITY_ORDER: Map<string, number> = new Map(HOME_COMMUNITY_IDS.map((id, index) => [id, index]));
const HOME_NAME_ORDER: Map<string, number> = new Map(["大型拆箱", "酱紫社区", "杂鱼日常"].map((name, index) => [name, index]));
const CANONICAL_COMMUNITY_BY_NAME = new Map([
  ["大型拆箱", "community-unboxing"],
  ["酱紫社区", "community-campus"],
  ["杂鱼日常", "community-daily"],
]);

function homeOrder(item: Community): number {
  return HOME_COMMUNITY_ORDER.get(item.id)
    ?? HOME_NAME_ORDER.get(item.name.trim())
    ?? 99;
}

export function compareHomeCommunity(a: Community, b: Community): number {
  return homeOrder(a) - homeOrder(b) || a.sortOrder - b.sortOrder || a.id.localeCompare(b.id);
}

/** 复刻 Flutter 首页的固定三板块与旧 ID/导入 ID 兼容去重策略。 */
export function selectHomeCommunities(source: Community[]): Community[] {
  const candidates = source
    .filter((item) => (item.status || "active") === "active")
    .filter((item) => {
      if (item.id === "community_qa" || item.slug === "qa" || item.name.trim() === "QA测试板块") return false;
      return HOME_COMMUNITY_IDS.includes(item.id as (typeof HOME_COMMUNITY_IDS)[number])
        || item.id.startsWith("community-import-")
        || HOME_COMMUNITY_NAMES.has(item.name.trim());
    })
    .sort(compareHomeCommunity);

  const seenIds = new Set<string>();
  const seenNames = new Set<string>();
  return candidates.filter((item) => {
    const name = item.name.trim();
    if (!item.id || seenIds.has(item.id) || seenNames.has(name)) return false;
    seenIds.add(item.id);
    seenNames.add(name);
    return true;
  });
}

/** 完整社区目录保留非首页板块，但把旧 ID/导入 ID 合并为一个逻辑板块。 */
export function normalizeCommunityDirectory(source: Community[]): Community[] {
  const sorted = source
    .filter((item) => (item.status || "active") === "active")
    .sort((a, b) => {
      const canonicalA = CANONICAL_COMMUNITY_BY_NAME.get(a.name.trim());
      const canonicalB = CANONICAL_COMMUNITY_BY_NAME.get(b.name.trim());
      if (canonicalA && a.id === canonicalA && !(canonicalB && b.id === canonicalB)) return -1;
      if (canonicalB && b.id === canonicalB && !(canonicalA && a.id === canonicalA)) return 1;
      return a.sortOrder - b.sortOrder || a.id.localeCompare(b.id);
    });

  const seenNames = new Set<string>();
  return sorted.filter((item) => {
    const name = item.name.trim();
    if (!item.id || !name || seenNames.has(name)) return false;
    seenNames.add(name);
    return true;
  });
}
