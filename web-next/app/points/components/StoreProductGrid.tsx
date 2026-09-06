"use client";

import { Icon } from "../../../components/icons";
import type { StoreProduct } from "../../../types/forum";
import { StoreProductCard } from "./StoreProductCard";

interface StoreProductGridProps {
  products: StoreProduct[];
  loading: boolean;
  error: string;
  availablePoints: number;
  isGuest: boolean;
  onRedeem: (product: StoreProduct) => void;
  onGuestRegister: () => void;
  onReload: () => void;
}

export function StoreProductGrid({
  products,
  loading,
  error,
  availablePoints,
  isGuest,
  onRedeem,
  onGuestRegister,
  onReload,
}: StoreProductGridProps) {
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
          重新加载商品
        </button>
      </div>
    );
  }

  if (products.length === 0) {
    return (
      <div className="workbench-empty-compact">
        <div className="workbench-empty-icon">
          <Icon name="box" size={20} />
        </div>
        <div className="workbench-empty-text">
          <h3>暂无在售商品</h3>
          <p>更多精彩周边礼品正在筹备上架中，敬请期待！</p>
        </div>
      </div>
    );
  }

  return (
    <section className="points-store-grid">
      {products.map((item) => (
        <StoreProductCard
          key={item.id}
          product={item}
          availablePoints={availablePoints}
          isGuest={isGuest}
          onRedeem={onRedeem}
          onGuestRegister={onGuestRegister}
        />
      ))}
    </section>
  );
}
