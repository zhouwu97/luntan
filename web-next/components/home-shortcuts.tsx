"use client";

import Link from "next/link";
import { Icon } from "./icons";
import { useToast } from "./toast-context";

export function HomeShortcuts({ onFilterHot }: { onFilterHot?: () => void }) {
  const { showToast } = useToast();

  return (
    <div className="quick-grid home-shortcuts" aria-label="快捷入口">
      <Link href="/ranking" className="quick" aria-label="玩具排行榜">
        <span className="quick-icon">
          <Icon name="trophy" size={21} />
        </span>
        <span>玩具排行榜</span>
      </Link>

      <button
        type="button"
        className="quick"
        aria-label="热门帖子"
        onClick={() => {
          if (onFilterHot) {
            onFilterHot();
          }
          showToast("已切换到热门帖子");
        }}
      >
        <span className="quick-icon">
          <Icon name="flame" size={21} />
        </span>
        <span>热门帖子</span>
      </button>

      <button
        type="button"
        className="quick"
        aria-label="穿搭分享"
        onClick={() => {
          showToast("已切换到穿搭分享");
        }}
      >
        <span className="quick-icon">
          <Icon name="hanger" size={21} />
        </span>
        <span>穿搭分享</span>
      </button>

      <button
        type="button"
        className="quick"
        aria-label="活动"
        onClick={() => {
          showToast("活动页入口已保留");
        }}
      >
        <span className="quick-icon">
          <Icon name="calendar" size={21} />
        </span>
        <span>活动</span>
      </button>
    </div>
  );
}
