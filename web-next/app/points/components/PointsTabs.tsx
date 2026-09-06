"use client";

import { Icon } from "../../../components/icons";

export type PointsTab = "store" | "orders" | "transactions";

interface PointsTabsProps {
  activeTab: PointsTab;
  orderCount: number;
  onTabChange: (tab: PointsTab) => void;
}

export function PointsTabs({ activeTab, orderCount, onTabChange }: PointsTabsProps) {
  return (
    <div className="points-tabs-bar" role="tablist" aria-label="积分功能分类">
      <button
        type="button"
        role="tab"
        aria-selected={activeTab === "store"}
        className={`points-tab ${activeTab === "store" ? "active" : ""}`}
        onClick={() => onTabChange("store")}
      >
        <Icon name="box" size={16} />
        <span>积分商城</span>
      </button>
      <button
        type="button"
        role="tab"
        aria-selected={activeTab === "orders"}
        className={`points-tab ${activeTab === "orders" ? "active" : ""}`}
        onClick={() => onTabChange("orders")}
      >
        <Icon name="tag" size={16} />
        <span>兑换记录 {orderCount > 0 && `(${orderCount})`}</span>
      </button>
      <button
        type="button"
        role="tab"
        aria-selected={activeTab === "transactions"}
        className={`points-tab ${activeTab === "transactions" ? "active" : ""}`}
        onClick={() => onTabChange("transactions")}
      >
        <Icon name="history" size={16} />
        <span>积分明细</span>
      </button>
    </div>
  );
}
