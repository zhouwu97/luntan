"use client";

import { FormEvent, useEffect, useState } from "react";
import { Icon } from "../../../components/icons";
import { updateStoreOrderShipping } from "../../../lib/api/forum";
import { formatError } from "../../../lib/format";
import type { StoreOrder, StoreShippingInput } from "../../../types/forum";

interface ShippingDialogProps {
  order: StoreOrder | null;
  onClose: () => void;
  onSuccess: (updatedOrder: StoreOrder) => void;
}

export function ShippingDialog({ order, onClose, onSuccess }: ShippingDialogProps) {
  const [shippingInput, setShippingInput] = useState<StoreShippingInput>({
    recipientName: "",
    phone: "",
    province: "",
    city: "",
    district: "",
    addressDetail: "",
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!order) return;
    setError("");
    if (order.shipping) {
      setShippingInput({
        recipientName: order.shipping.recipientName || "",
        phone: order.shipping.phone || "",
        province: order.shipping.province || "",
        city: order.shipping.city || "",
        district: order.shipping.district || "",
        addressDetail: order.shipping.addressDetail || "",
      });
    } else {
      setShippingInput({
        recipientName: "",
        phone: "",
        province: "",
        city: "",
        district: "",
        addressDetail: "",
      });
    }
  }, [order]);

  if (!order) return null;

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!order) return;
    if (!shippingInput.recipientName.trim()) {
      setError("请填写收件人姓名");
      return;
    }
    if (!shippingInput.phone.trim()) {
      setError("请填写联系电话");
      return;
    }
    if (
      !shippingInput.province.trim() ||
      !shippingInput.city.trim() ||
      !shippingInput.addressDetail.trim()
    ) {
      setError("请填写完整省市及详细地址");
      return;
    }

    setBusy(true);
    setError("");
    try {
      const updatedOrder = await updateStoreOrderShipping(order.id, shippingInput);
      onSuccess(updatedOrder);
      onClose();
    } catch (err) {
      setError(formatError(err, "保存地址失败，请检查"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal-card"
        role="dialog"
        aria-modal="true"
        aria-label="填写收货地址"
        onClick={(e) => e.stopPropagation()}
        style={{ maxWidth: 460 }}
      >
        <div className="modal-head">
          <h3>填写收货地址</h3>
          <button type="button" className="modal-close" onClick={onClose}>
            <Icon name="close" size={18} />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="modal-form">
          <div className="form-item">
            <label>收件人姓名 *</label>
            <input
              type="text"
              required
              value={shippingInput.recipientName}
              onChange={(e) =>
                setShippingInput({ ...shippingInput, recipientName: e.target.value })
              }
              placeholder="如：张三"
            />
          </div>
          <div className="form-item">
            <label>联系电话 *</label>
            <input
              type="tel"
              required
              value={shippingInput.phone}
              onChange={(e) =>
                setShippingInput({ ...shippingInput, phone: e.target.value })
              }
              placeholder="如：13800000000"
            />
          </div>
          <div className="form-row-2">
            <div className="form-item">
              <label>省份 *</label>
              <input
                type="text"
                required
                value={shippingInput.province}
                onChange={(e) =>
                  setShippingInput({ ...shippingInput, province: e.target.value })
                }
                placeholder="省/直辖市"
              />
            </div>
            <div className="form-item">
              <label>城市 *</label>
              <input
                type="text"
                required
                value={shippingInput.city}
                onChange={(e) =>
                  setShippingInput({ ...shippingInput, city: e.target.value })
                }
                placeholder="市"
              />
            </div>
          </div>
          <div className="form-item">
            <label>区/县</label>
            <input
              type="text"
              value={shippingInput.district}
              onChange={(e) =>
                setShippingInput({ ...shippingInput, district: e.target.value })
              }
              placeholder="区/县（选填）"
            />
          </div>
          <div className="form-item">
            <label>详细街道地址 *</label>
            <textarea
              required
              rows={3}
              value={shippingInput.addressDetail}
              onChange={(e) =>
                setShippingInput({ ...shippingInput, addressDetail: e.target.value })
              }
              placeholder="道路门牌、小区楼栋与门牌号"
            />
          </div>

          {error && <div className="form-error">{error}</div>}

          <div className="modal-actions">
            <button
              type="button"
              className="outline-button"
              disabled={busy}
              onClick={onClose}
            >
              取消
            </button>
            <button type="submit" className="primary-button" disabled={busy}>
              {busy ? "正在保存…" : "保存收货地址"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
