"use client";

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
  onSortChange,
  onLatestOrderChange,
  hasMedia,
  filterOpen,
  onFilterToggle,
  onMediaChange,
  canPublish,
}: {
  sort: FeedSort;
  latestOrder: LatestOrder;
  onSortChange: (value: FeedSort) => void;
  onLatestOrderChange: (value: LatestOrder) => void;
  hasMedia?: boolean;
  filterOpen?: boolean;
  onFilterToggle?: () => void;
  onMediaChange?: (value: boolean) => void;
  canPublish?: boolean;
}) {
  return (
    <div className="feedbar feed-toolbar">
      <div className="feed-tabs" role="tablist" aria-label="帖子流排序">
        <div className="tab-row">
          {tabs.map((tab) => (
            <button
              key={tab.value}
              type="button"
              role="tab"
              aria-selected={sort === tab.value}
              className={`feed-tab tab${sort === tab.value ? " active" : ""}`}
              onClick={() => onSortChange(tab.value)}
            >
              {tab.label}
            </button>
          ))}
        </div>

        <div className="sort-switch order-pill" role="group" aria-label="最新排序方式">
          <button
            type="button"
            className={latestOrder === "comment" ? "active" : ""}
            onClick={() => {
              if (sort !== "latest") onSortChange("latest");
              onLatestOrderChange("comment");
            }}
          >
            按回复
          </button>
          <button
            type="button"
            className={latestOrder === "post" ? "active" : ""}
            onClick={() => {
              if (sort !== "latest") onSortChange("latest");
              onLatestOrderChange("post");
            }}
          >
            按发帖
          </button>
        </div>
      </div>
    </div>
  );
}
