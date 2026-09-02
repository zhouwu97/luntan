import { Icon, type IconName } from "./icons";
import type { Community } from "../types/forum";

const communityStyle: Record<string, { icon: IconName; tone: string }> = {
  酱紫社区: { icon: "trophy", tone: "lilac" },
  大型拆箱: { icon: "box", tone: "orange" },
  杂鱼日常: { icon: "sparkle", tone: "mint" },
};

export function HomeCommunityTabs({
  communities,
  activeId,
  onSelect,
}: {
  communities: Community[];
  activeId?: string;
  onSelect: (community: Community) => void;
}) {
  if (!communities.length) return <div className="home-community-tabs-empty" role="status">首页板块加载中…</div>;
  return (
    <div className="home-community-tabs" role="tablist" aria-label="首页社区">
      {communities.map((community) => {
        const style = communityStyle[community.name] ?? { icon: "sparkle" as IconName, tone: "blue" };
        const active = community.id === activeId;
        return (
          <button key={community.id} type="button" role="tab" aria-selected={active} className={`home-community-tab${active ? " active" : ""}`} onClick={() => onSelect(community)}>
            <span className={`community-icon ${style.tone}`}><Icon name={style.icon} size={18} /></span>
            <span>{community.name}</span>
          </button>
        );
      })}
    </div>
  );
}

