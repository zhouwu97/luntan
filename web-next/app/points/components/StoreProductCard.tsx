"use client";

import { useState } from "react";
import type { StoreProduct } from "../../../types/forum";

interface StoreProductCardProps {
  product: StoreProduct;
  availablePoints: number;
  isGuest: boolean;
  onRedeem: (product: StoreProduct) => void;
  onGuestRegister: () => void;
}

export function StoreProductCard({
  product,
  availablePoints,
  isGuest,
  onRedeem,
  onGuestRegister,
}: StoreProductCardProps) {
  const [imgError, setImgError] = useState(false);
  const isOutOfStock = product.stock !== undefined && product.stock <= 0;
  const canAfford = availablePoints >= product.points;

  return (
    <div className="store-product-card">
      <div className="product-media-frame">
        {product.imageUrl && !imgError ? (
          <img
            src={product.imageUrl}
            alt={product.name}
            className="product-img"
            loading="lazy"
            onError={() => setImgError(true)}
          />
        ) : (
          <div className="product-emoji-placeholder">
            <span className="product-emoji">{product.emoji || "🎁"}</span>
          </div>
        )}
        <span className="product-points-tag">🪙 {product.points} 积分</span>
      </div>

      <div className="product-info">
        <h3 className="product-name">{product.name}</h3>
        <p className="product-desc">{product.description || "社区专属纪念周边实物礼品"}</p>

        <div className="product-meta-row">
          <span className="product-redeemed">
            已兑换 {product.redeemedCount || 0} 件
            {product.stock !== undefined && ` · 剩余库存 ${product.stock}`}
          </span>

          {isOutOfStock ? (
            <button type="button" className="product-action-btn disabled" disabled>
              已售罄
            </button>
          ) : isGuest ? (
            <button
              type="button"
              className="product-action-btn guest"
              onClick={onGuestRegister}
            >
              注册后兑换
            </button>
          ) : canAfford ? (
            <button
              type="button"
              className="product-action-btn primary"
              onClick={() => onRedeem(product)}
            >
              申请兑换
            </button>
          ) : (
            <button type="button" className="product-action-btn disabled" disabled>
              积分不足 (差 {product.points - availablePoints})
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
