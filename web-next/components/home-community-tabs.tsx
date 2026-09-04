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
  const isAllActive = !activeId || activeId === "all";

  if (!communities.length) {
    return (
      <div className="community-tabs" role="tablist" aria-label="首页社区">
        <button
          type="button"
          className={`community-tab${isAllActive ? " active" : ""}`}
          onClick={() => onSelect(undefined)}
        >
          全部
        </button>
        {preferredOrder.map((name) => (
          <button
            key={name}
            type="button"
            className="community-tab"
          >
            {name}
          </button>
        ))}
      </div>
    );
  }

  // Sort according to preferred order if matches
  const sorted = [...communities].sort((a, b) => {
    const idxA = preferredOrder.indexOf(a.name.trim());
    const idxB = preferredOrder.indexOf(b.name.trim());
    if (idxA !== -1 && idxB !== -1) return idxA - idxB;
    if (idxA !== -1) return -1;
    if (idxB !== -1) return 1;
    return 0;
  });

  return (
    <div className="community-tabs" role="tablist" aria-label="首页社区">
      <button
        type="button"
        role="tab"
        aria-selected={isAllActive}
        className={`community-tab${isAllActive ? " active" : ""}`}
        onClick={() => onSelect(undefined)}
      >
        全部
      </button>
      {sorted.map((community) => {
        const active = community.id === activeId;
        return (
          <button
            key={community.id}
            type="button"
            role="tab"
            aria-selected={active}
            className={`community-tab${active ? " active" : ""}`}
            onClick={() => onSelect(community)}
          >
            {community.name}
          </button>
        );
      })}
    </div>
  );
}
