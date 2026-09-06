"use client";

import { useEffect, useRef, useState } from "react";
import { apiJson } from "../../../lib/api/client";
import { formatError } from "../../../lib/format";
import type { StoreOrder } from "../../../types/forum";

type Aftercare = { status: string; fulfillment_status: string; reason: string; return_instructions: string; carrier: string; tracking_no: string; refunded_points: number };
export const aftercareLabels: Record<string, string> = { cancelled: "已取消", return_requested: "退货待审核", refund_pending: "已同意退货 · 待退款", refunded: "已退款" };

export function AftercareDialog({ order, onClose, onSuccess }: { order: StoreOrder; onClose: () => void; onSuccess: () => void }) {
  const [data, setData] = useState<Aftercare>();
  const [reason, setReason] = useState("");
  const [carrier, setCarrier] = useState("");
  const [tracking, setTracking] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [retry, setRetry] = useState(0);
  const keys = useRef(new Map<string, string>());
  const inFlight = useRef(false);
  const base = `/me/store-orders/${encodeURIComponent(order.id)}`;
  useEffect(() => {
    let active = true;
    setError("");
    void apiJson<Aftercare>(`${base}/aftercare`).then((value) => { if (active) setData(value); }).catch((err) => { if (active) setError(formatError(err, "售后信息加载失败")); });
    return () => { active = false; };
  }, [base, retry]);

  async function submit(action: string) {
    if (inFlight.current) return;
    if (!reason.trim()) { setError("请填写操作说明"); return; }
    if (action === "return_shipping" && (!carrier.trim() || !tracking.trim())) { setError("请填写回寄物流公司和单号"); return; }
    const body = JSON.stringify({ action, reason: reason.trim(), ...(action === "return_shipping" ? { carrier: carrier.trim(), tracking_no: tracking.trim() } : {}) });
    // 请求结果不确定时保留原键，重复点击不会重复执行退款。
    const key = keys.current.get(body) || crypto.randomUUID();
    keys.current.set(body, key);
    inFlight.current = true;
    setBusy(true); setError("");
    try {
      await apiJson(`${base}/reverse`, { method: "POST", body, headers: { "Idempotency-Key": key } });
      keys.current.delete(body);
      onSuccess(); onClose();
    } catch (err) { setError(formatError(err, "操作失败，请重试")); }
    finally { inFlight.current = false; setBusy(false); }
  }
  const status = data?.status;
  const fs = data?.fulfillment_status;
  const canCancel = status === "pending_review" || (status === "approved" && (fs === "awaiting_address" || fs === "ready_to_ship"));
  const canReturn = status === "approved" && (fs === "shipped" || fs === "completed");
  const canShipReturn = status === "approved" && fs === "refund_pending";
  return <div className="modal-backdrop" role="presentation"><section className="modal-card" role="dialog" aria-modal="true" aria-label="取消与售后" style={{ width: "min(520px, calc(100vw - 32px))", maxHeight: "85dvh", overflowY: "auto", padding: 24 }}>
    <h2>取消与售后</h2><p>{order.productName}</p>
    {error && <p role="alert">{error}</p>}
    {!data ? <button type="button" className="outline-button" onClick={() => setRetry((v) => v + 1)}>{error ? "重新加载" : "正在加载…"}</button> : <>
      {fs && aftercareLabels[fs] && <p>{aftercareLabels[fs]}</p>}
      {data.refunded_points > 0 && <p>已返还 {data.refunded_points} 积分</p>}
      {data.reason && <p>最新说明：{data.reason}</p>}
      {data.return_instructions && <p style={{ whiteSpace: "pre-wrap" }}>回寄要求：{data.return_instructions}</p>}
      {data.tracking_no && <p>回寄物流：{data.carrier} {data.tracking_no}</p>}
      {(canCancel || canReturn || canShipReturn) && <>
        <label style={{ display: "block", marginBlock: 16 }}>操作说明（必填）<textarea autoFocus maxLength={1000} disabled={busy} value={reason} onChange={(e) => setReason(e.target.value)} rows={3} style={{ display: "block", width: "100%" }} /></label>
        {canShipReturn && <><label style={{ display: "block", marginBottom: 12 }}>回寄物流公司<input maxLength={40} disabled={busy} value={carrier} onChange={(e) => setCarrier(e.target.value)} /></label><label style={{ display: "block", marginBottom: 12 }}>回寄物流单号<input maxLength={80} disabled={busy} value={tracking} onChange={(e) => setTracking(e.target.value)} /></label></>}
        {canCancel && <button type="button" className="outline-button" disabled={busy} onClick={() => submit("cancel")}>取消订单并返还已扣积分</button>}
        {canReturn && <button type="button" className="outline-button" disabled={busy} onClick={() => submit("request_return")}>申请退货</button>}
        {canShipReturn && <button type="button" className="outline-button" disabled={busy} onClick={() => submit("return_shipping")}>提交回寄物流</button>}
      </>}
    </>}
    <button type="button" className="outline-button" disabled={busy} onClick={onClose} style={{ marginTop: 16, marginLeft: 8 }}>关闭</button>
  </section></div>;
}
