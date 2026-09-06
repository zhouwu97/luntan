"use client";

import { useEffect, useRef } from "react";
import { Icon } from "../../../components/icons";
import type { StoreOrder } from "../../../types/forum";
import { OrderCard } from "./OrderCard";

interface OrderListProps {
  orders: StoreOrder[];
  loading: boolean;
  loadingMore: boolean;
  hasMore: boolean;
  nextCursor?: string;
  error: string;
  loadMoreError: string;
  highlightOrderId?: string;
  onOpenShipping: (order: StoreOrder) => void;
  onComplete: (order: StoreOrder) => void;
  onAftercare: (order: StoreOrder) => void;
  onReload: () => void;
  onLoadMore: () => void;
  onGoStore: () => void;
}

export function OrderList({
  orders,
  loading,
  loadingMore,
  hasMore,
  nextCursor,
  error,
  loadMoreError,
  highlightOrderId,
  onOpenShipping,
  onComplete,
  onAftercare,
  onReload,
  onLoadMore,
  onGoStore,
}: OrderListProps) {
  const sentinelRef = useRef<HTMLDivElement | null>(null);

  // Sprint 5: IntersectionObserver 真正自动加载下一页
  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (!sentinel) return;

    const observer = new IntersectionObserver(
      (entries) => {
        const first = entries[0];
        if (first && first.isIntersecting && hasMore && !loadingMore && nextCursor) {
          onLoadMore();
        }
      },
      { rootMargin: "150px" }
    );

    observer.observe(sentinel);
    return () => {
      observer.disconnect();
    };
  }, [hasMore, loadingMore, nextCursor, onLoadMore]);

  // Sprint 3: 深链定位滚动
  useEffect(() => {
    if (!highlightOrderId) return;
    const el = document.getElementById(`order-${highlightOrderId}`);
    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }, [highlightOrderId, orders]);

  if (loading) {
    return (
      <div className="detail-skeleton">
        <div />
        <div />
      </div>
    );
  }

  if (error) {
    return (
      <div className="points-error-box">
        <p>{error}</p>
        <button type="button" className="outline-button" onClick={onReload}>
          重新加载兑换记录
        </button>
      </div>
    );
  }

  if (orders.length === 0) {
    return (
      <div className="workbench-empty-compact">
        <div className="workbench-empty-icon">
          <Icon name="box" size={20} />
        </div>
        <div className="workbench-empty-text">
          <h3>暂无兑换记录</h3>
          <p>您还没有兑换过社区商品，快去挑选心仪的周边吧</p>
        </div>
        <button
          type="button"
          className="workbench-empty-action"
          onClick={onGoStore}
        >
          去逛商城
        </button>
      </div>
    );
  }

  return (
    <section className="points-orders-section">
      <div className="orders-list">
        {orders.map((order) => (
          <OrderCard
            key={order.id}
            order={order}
            isHighlighted={order.id === highlightOrderId}
            onOpenShipping={onOpenShipping}
            onComplete={onComplete}
            onAftercare={onAftercare}
          />
        ))}
      </div>

      {/* 底部哨兵与状态提示 */}
      <div
        ref={sentinelRef}
        style={{
          padding: "16px 0",
          textAlign: "center",
          fontSize: 13,
          color: "var(--text-faint)",
        }}
      >
        {loadingMore && <span>正在加载更多记录…</span>}
        {loadMoreError && (
          <button
            type="button"
            className="outline-button"
            style={{ fontSize: 12, padding: "4px 12px" }}
            onClick={onLoadMore}
          >
            {loadMoreError}
          </button>
        )}
        {!hasMore && orders.length > 0 && !loadingMore && !loadMoreError && (
          <span>已经到底了</span>
        )}
      </div>
    </section>
  );
}
