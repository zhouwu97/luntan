"use client";

import { Icon } from "../../../components/icons";
import { relativeTime } from "../../../lib/format";
import type { StoreOrder } from "../../../types/forum";
import { aftercareLabels } from "./AftercareDialog";

interface OrderCardProps {
  order: StoreOrder;
  isHighlighted?: boolean;
  onOpenShipping: (order: StoreOrder) => void;
  onComplete: (order: StoreOrder) => void;
  onAftercare: (order: StoreOrder) => void;
}

export function OrderCard({
  order,
  isHighlighted,
  onOpenShipping,
  onComplete,
  onAftercare,
}: OrderCardProps) {
  const isApproved = order.status === "approved";
  const canEditShipping =
    isApproved &&
    (order.fulfillmentStatus === "awaiting_address" ||
      order.fulfillmentStatus === "ready_to_ship");
  const canComplete = isApproved && order.fulfillmentStatus === "shipped";

  return (
    <div
      id={`order-${order.id}`}
      className={`order-card${isHighlighted ? " highlighted" : ""}`}
    >
      <div className="order-header">
        <div className="order-title-box">
          <strong className="order-prod-name">{order.productName}</strong>
          <span className="order-date">{relativeTime(order.createdAt)} 申请</span>
        </div>
        <div className="order-status-badge-wrap">
          {aftercareLabels[order.fulfillmentStatus] && <span className="badge neutral">{aftercareLabels[order.fulfillmentStatus]}</span>}
          {order.status === "pending_review" && (
            <span className="badge warning">审核中</span>
          )}
          {order.status === "rejected" && (
            <span className="badge danger">
              未通过: {order.reviewReason || "未说明原因"}
            </span>
          )}
          {isApproved && order.fulfillmentStatus === "awaiting_address" && (
            <span className="badge info">待填写收货地址</span>
          )}
          {isApproved && order.fulfillmentStatus === "ready_to_ship" && (
            <span className="badge success">待发货</span>
          )}
          {isApproved && order.fulfillmentStatus === "shipped" && (
            <span className="badge success">已发货</span>
          )}
          {isApproved && order.fulfillmentStatus === "completed" && (
            <span className="badge neutral">已完成</span>
          )}
        </div>
      </div>

      <div className="order-body">
        <div className="order-points-deduct">
          {order.fulfillmentStatus === "refunded" ? "已返还" : order.fulfillmentStatus === "cancelled" ? "已取消，已扣积分已返还；申请积分" : isApproved ? "已扣除" : "申请积分"}: <strong>{order.points} 积分</strong>
        </div>

        {/* 物流发货信息 */}
        {order.shipping?.trackingNo && (
          <div className="order-tracking-info">
            <span className="carrier-name">{order.shipping.carrier || "快递配送"}</span>
            <span className="tracking-num">单号：{order.shipping.trackingNo}</span>
          </div>
        )}

        {/* 已有收件地址摘要 */}
        {order.shipping?.recipientName && (
          <div className="order-address-summary">
            收件人：{order.shipping.recipientName} ({order.shipping.phone}) <br />
            地址：{order.shipping.province}
            {order.shipping.city}
            {order.shipping.district || ""}
            {order.shipping.addressDetail}
          </div>
        )}

        {/* 操作区 */}
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginTop: 8 }}>
          <button type="button" className="order-shipping-edit-btn" onClick={() => onAftercare(order)}>取消与售后</button>
          {canEditShipping && (
            <button
              type="button"
              className="order-shipping-edit-btn"
              onClick={() => onOpenShipping(order)}
            >
              <Icon name="edit" size={14} />
              <span>
                {order.shipping?.recipientName ? "修改收货地址" : "填写收货地址"}
              </span>
            </button>
          )}

          {canComplete && (
            <button
              type="button"
              className="order-complete-btn"
              onClick={() => onComplete(order)}
            >
              <Icon name="check" size={14} />
              <span>确认已收到</span>
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
