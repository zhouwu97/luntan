"use client";

import type { Community } from "../types/forum";

const preferredOrder = ["大型拆箱", "酱紫社区", "杂鱼日常"];

export function HomeCommunityTabs({
  communities,
  activeId,
  onSelect,
}: {
  communities: Community[];
  activeId?: string;
  onSelect: (community?: Community) => void;
}) {
  // 严格只展示三个核心板块，对齐 Flutter 首页真源（无“全部”冗余项）
  const filtered = communities.filter((c) => preferredOrder.includes(c.name.trim()));
  const sorted = (filtered.length ? filtered : communities).sort((a, b) => {
    const idxA = preferredOrder.indexOf(a.name.trim());
    const idxB = preferredOrder.indexOf(b.name.trim());
    return (idxA !== -1 ? idxA : 99) - (idxB !== -1 ? idxB : 99);
  });

  const displayList = sorted.length
    ? sorted
    : preferredOrder.map((name, index) => ({
        id: `fallback-${index}`,
        slug: `slug-${index}`,
        name,
        sortOrder: index,
      } as Community));

  return (
    <div className="home-community-tabs" role="tablist" aria-label="首页社区板块切换">
      {displayList.map((community) => {
        const isCampus = community.name.trim() === "酱紫社区";
        // 若没有显式指定 activeId，在移动端语义上高亮“酱紫社区”
        const isActive = activeId
          ? community.id === activeId || community.name.trim() === activeId
          : isCampus;

        return (
          <button
            key={community.id || community.name}
            type="button"
            role="tab"
            aria-selected={isActive}
            className={`home-community-tab${isActive ? " active" : ""}${isCampus ? " campus-art-tab" : ""}`}
            onClick={() => onSelect(community)}
          >
            {isCampus ? (
              <span className="campus-art-label">
                <span className="campus-star">✦</span> 酱紫社区
              </span>
            ) : (
              <span>{community.name}</span>
            )}
          </button>
        );
      })}
    </div>
  );
}
