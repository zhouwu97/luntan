import { Icon, type IconName } from "./icons";
import type { Community } from "../types/forum";
import Link from "next/link";

const communityStyle: Record<string, { icon: IconName; tone: string }> = {
  酱紫社区: { icon: "trophy", tone: "lilac" },
  大型拆箱: { icon: "box", tone: "orange" },
  杂鱼日常: { icon: "sparkle", tone: "mint" },
};

export function CommunityRail({
  communities,
  activeId,
  onSelect,
}: {
  communities: Community[];
  activeId?: string;
  onSelect: (community: Community | undefined) => void;
}) {
  return (
    <aside className="community-rail rail-panel" aria-label="社区导航">
      <div className="rail-heading">
        <h2>首页板块</h2>
      </div>
      <div className="community-list">
        {communities.map((community) => {
          const style = communityStyle[community.name] ?? { icon: "sparkle" as IconName, tone: "blue" };
          const active = community.id === activeId;
          return (
            <button
              type="button"
              key={community.id}
              className={`community-item${active ? " active" : ""}`}
              onClick={() => onSelect(community)}
            >
              <span className={`community-icon ${style.tone}`}><Icon name={style.icon} size={20} /></span>
              <span className="community-copy">
                <strong>{community.name}</strong>
                <small>{community.description || "和同好聊聊最近的新发现"}</small>
              </span>
              <Icon name="chevron-right" size={17} className="community-chevron" />
            </button>
          );
        })}
      </div>
      <Link href="/communities" className="browse-all">
        浏览全部社区 <Icon name="arrow-up-right" size={16} />
      </Link>
    </aside>
  );
}
