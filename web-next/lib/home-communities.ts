import type { Community } from "../types/forum";

export const HOME_COMMUNITY_IDS = [
  "community-unboxing",
  "community-campus",
  "community-daily",
] as const;

const HOME_COMMUNITY_NAMES = new Set(["大型拆箱", "酱紫社区", "杂鱼日常"]);
const HOME_COMMUNITY_ORDER: Map<string, number> = new Map(HOME_COMMUNITY_IDS.map((id, index) => [id, index]));
const HOME_NAME_ORDER: Map<string, number> = new Map(["大型拆箱", "酱紫社区", "杂鱼日常"].map((name, index) => [name, index]));

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
