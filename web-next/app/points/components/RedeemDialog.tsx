"use client";

import { Icon } from "../../../components/icons";
import type { StoreProduct } from "../../../types/forum";

interface RedeemDialogProps {
  product: StoreProduct | null;
  busy: boolean;
  onClose: () => void;
  onConfirm: () => Promise<void>;
}

export function RedeemDialog({
  product,
  busy,
  onClose,
  onConfirm,
}: RedeemDialogProps) {
  if (!product) return null;

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal-card"
        role="dialog"
        aria-modal="true"
        aria-label="申请兑换"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="modal-head">
          <h3>申请兑换</h3>
          <button type="button" className="modal-close" onClick={onClose}>
            <Icon name="close" size={18} />
          </button>
        </div>
        <div className="modal-body">
          <p>
            商品：<strong>{product.name}</strong>
            <br />
            所需积分：<strong>{product.points} PTS</strong>
          </p>
          <div
            style={{
              marginTop: 12,
              padding: "10px 14px",
              background: "#f8fafc",
              border: "1px solid #e2e8f0",
              borderRadius: 8,
              fontSize: 13,
              color: "#475569",
              lineHeight: 1.6,
            }}
          >
            提交后将进入人工审核。
            <br />
            审核通过后才会正式扣除积分，届时系统会通知你填写收货信息。
          </div>
        </div>
        <div className="modal-actions">
          <button
            type="button"
            className="outline-button"
            disabled={busy}
            onClick={onClose}
          >
            取消
          </button>
          <button
            type="button"
            className="primary-button"
            disabled={busy}
            onClick={onConfirm}
          >
            {busy ? "正在提交…" : "提交申请"}
          </button>
        </div>
      </div>
    </div>
  );
}
