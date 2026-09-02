import Link from "next/link";
import { Icon } from "./icons";

export type FeedSort = "recommended" | "latest" | "hot";
export type LatestOrder = "comment" | "post";

const tabs: Array<{ label: string; value: FeedSort }> = [
  { label: "推荐", value: "recommended" },
  { label: "最新", value: "latest" },
  { label: "热门", value: "hot" },
];

export function FeedToolbar({
  sort,
  latestOrder,
  hasMedia,
  filterOpen,
  onSortChange,
  onLatestOrderChange,
  onFilterToggle,
  onMediaChange,
  canPublish,
}: {
  sort: FeedSort;
  latestOrder: LatestOrder;
  hasMedia: boolean;
  filterOpen: boolean;
  onSortChange: (value: FeedSort) => void;
  onLatestOrderChange: (value: LatestOrder) => void;
  onFilterToggle: () => void;
  onMediaChange: (value: boolean) => void;
  canPublish: boolean;
}) {
  return (
    <div className="feed-toolbar">
      <div className="feed-tabs" role="tablist" aria-label="帖子排序">
        {tabs.map((tab) => <button key={tab.value} type="button" role="tab" aria-selected={sort === tab.value} className={`feed-tab${sort === tab.value ? " active" : ""}`} onClick={() => onSortChange(tab.value)}>{tab.label}</button>)}
      </div>
      <div className="feed-toolbar-right">
        {sort === "latest" && <div className="latest-order" role="group" aria-label="最新排序方式"><button type="button" className={latestOrder === "comment" ? "active" : ""} onClick={() => onLatestOrderChange("comment")}>按回复</button><button type="button" className={latestOrder === "post" ? "active" : ""} onClick={() => onLatestOrderChange("post")}>按发帖</button></div>}
        <div className="feed-tools">
          <button type="button" className={`filter-button${filterOpen || hasMedia ? " active" : ""}`} aria-expanded={filterOpen} onClick={onFilterToggle}><Icon name="filter" size={16} />筛选{hasMedia && <span className="filter-count">1</span>}</button>
          {filterOpen && <div className="filter-popover"><label><input type="checkbox" checked={hasMedia} onChange={(event) => onMediaChange(event.target.checked)} /> 只看有图片</label></div>}
        </div>
        {canPublish && <Link href="/publish" className="mobile-feed-publish"><Icon name="plus" size={15} />发布</Link>}
      </div>
    </div>
  );
}

