"use client";

import Link from "next/link";
import { FormEvent, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { SiteHeader } from "../../components/site-header";
import { BottomNav } from "../../components/bottom-nav";
import { AppDownloadBanner } from "../../components/app-download-banner";
import { Icon } from "../../components/icons";
import { useSession } from "../../components/session-provider";
import { useToast } from "../../components/toast-context";
import {
  createStoreOrder,
  getMyPointsDetail,
  getMyStoreOrders,
  getStoreProducts,
  updateStoreOrderShipping,
} from "../../lib/api/forum";
import { compactCount, formatError, relativeTime } from "../../lib/format";
import type {
  PointTransaction,
  StoreOrder,
  StoreProduct,
  StoreShippingInput,
} from "../../types/forum";

type PointsTab = "store" | "orders" | "transactions";

export default function PointsCenterPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { user, ready, isGuest, isRegistered } = useSession();
  const { showToast } = useToast();

  const initialTab = (searchParams.get("tab") as PointsTab) || "store";
  const [activeTab, setActiveTab] = useState<PointsTab>(
    initialTab === "orders" || initialTab === "transactions" ? initialTab : "store"
  );

  const [balance, setBalance] = useState<number>(0);
  const [products, setProducts] = useState<StoreProduct[]>([]);
  const [orders, setOrders] = useState<StoreOrder[]>([]);
  const [transactions, setTransactions] = useState<PointTransaction[]>([]);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  // 弹窗状态
  const [rulesOpen, setRulesOpen] = useState(false);
  const [selectedProduct, setSelectedProduct] = useState<StoreProduct | null>(null);
  const [redeemBusy, setRedeemBusy] = useState(false);

  // 地址表单弹窗
  const [shippingOrder, setShippingOrder] = useState<StoreOrder | null>(null);
  const [shippingInput, setShippingInput] = useState<StoreShippingInput>({
    recipientName: "",
    phone: "",
    province: "",
    city: "",
    district: "",
    addressDetail: "",
  });
  const [shippingBusy, setShippingBusy] = useState(false);
  const [shippingError, setShippingError] = useState("");

  // 加载数据
  useEffect(() => {
    if (!ready) return;
    let mounted = true;
    setLoading(true);
    setError("");

    const loadData = async () => {
      try {
        const [prodList, pointsData] = await Promise.all([
          getStoreProducts().catch(() => []),
          user ? getMyPointsDetail().catch(() => ({ balance: 0, transactions: [] })) : Promise.resolve({ balance: 0, transactions: [] }),
        ]);

        if (!mounted) return;
        setProducts(prodList);
        setBalance(pointsData.balance);
        setTransactions(pointsData.transactions);

        if (user) {
          const orderPage = await getMyStoreOrders().catch(() => ({ items: [], hasMore: false }));
          if (mounted) setOrders(orderPage.items);
        }
      } catch (err) {
        if (mounted) setError(formatError(err, "加载积分数据失败"));
      } finally {
        if (mounted) setLoading(false);
      }
    };

    void loadData();

    return () => {
      mounted = false;
    };
  }, [ready, user]);

  // 处理兑换提交
  async function handleConfirmRedeem() {
    if (!selectedProduct) return;
    if (!isRegistered) {
      router.push(`/login?mode=register&next=${encodeURIComponent("/points")}`);
      return;
    }
    setRedeemBusy(true);
    try {
      const order = await createStoreOrder(selectedProduct.id);
      showToast(`兑换成功！已提交「${selectedProduct.name}」`);
      setBalance((curr) => Math.max(0, curr - selectedProduct.points));
      setOrders((prev) => [order, ...prev]);
      setSelectedProduct(null);
      setActiveTab("orders");
    } catch (err) {
      showToast(formatError(err, "兑换提交失败，请稍后再试"));
    } finally {
      setRedeemBusy(false);
    }
  }

  // 打开填写地址弹窗
  function handleOpenShipping(order: StoreOrder) {
    setShippingOrder(order);
    setShippingError("");
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
  }

  // 提交收货地址
  async function handleSubmitShipping(e: FormEvent) {
    e.preventDefault();
    if (!shippingOrder) return;
    if (!shippingInput.recipientName.trim()) {
      setShippingError("请填写收件人姓名");
      return;
    }
    if (!shippingInput.phone.trim()) {
      setShippingError("请填写联系电话");
      return;
    }
    if (!shippingInput.province.trim() || !shippingInput.city.trim() || !shippingInput.addressDetail.trim()) {
      setShippingError("请填写完整省市及详细地址");
      return;
    }

    setShippingBusy(true);
    setShippingError("");
    try {
      const updatedOrder = await updateStoreOrderShipping(shippingOrder.id, shippingInput);
      showToast("收货地址已保存，待仓库发货！");
      setOrders((prev) =>
        prev.map((o) => (o.id === updatedOrder.id ? updatedOrder : o))
      );
      setShippingOrder(null);
    } catch (err) {
      setShippingError(formatError(err, "保存地址失败，请检查"));
    } finally {
      setShippingBusy(false);
    }
  }

  return (
    <>
      <SiteHeader />

      <main className="page-frame points-page" style={{ maxWidth: 960, margin: "0 auto", padding: "20px 16px 80px" }}>
        {/* 顶部导航返回 */}
        <div className="points-top-nav">
          <Link href="/me" className="back-link">
            <Icon name="chevron-left" size={17} />
            <span>返回我的工作台</span>
          </Link>
        </div>

        {/* 积分总览卡片 */}
        <section className="points-hero-card">
          <div className="points-hero-left">
            <span className="points-hero-label">我的可用积分</span>
            <div className="points-hero-val-row">
              <strong className="points-hero-number">{compactCount(balance)}</strong>
              <span className="points-unit">PTS</span>
            </div>
            <p className="points-hero-tip">
              发帖、参与精彩评论与同好点赞均可获得积分，积攒可兑换正版实物礼品。
            </p>
          </div>

          <div className="points-hero-right">
            <button
              type="button"
              className="points-rule-btn"
              onClick={() => setRulesOpen(true)}
            >
              <Icon name="info" size={15} />
              <span>积分规则说明</span>
            </button>
            {isGuest && (
              <button
                type="button"
                className="points-upgrade-btn"
                onClick={() => router.push(`/login?mode=register&next=${encodeURIComponent("/points")}`)}
              >
                注册升级账号
              </button>
            )}
          </div>
        </section>

        {/* 导航 Tabs */}
        <div className="points-tabs-bar">
          <button
            type="button"
            className={`points-tab ${activeTab === "store" ? "active" : ""}`}
            onClick={() => setActiveTab("store")}
          >
            <Icon name="box" size={16} />
            <span>积分商城</span>
          </button>
          <button
            type="button"
            className={`points-tab ${activeTab === "orders" ? "active" : ""}`}
            onClick={() => setActiveTab("orders")}
          >
            <Icon name="tag" size={16} />
            <span>兑换记录 {orders.length > 0 && `(${orders.length})`}</span>
          </button>
          <button
            type="button"
            className={`points-tab ${activeTab === "transactions" ? "active" : ""}`}
            onClick={() => setActiveTab("transactions")}
          >
            <Icon name="history" size={16} />
            <span>积分明细</span>
          </button>
        </div>

        {error && <div className="data-note" role="status" style={{ marginBottom: 16 }}>{error}</div>}

        {/* 内容展示区 */}
        {loading ? (
          <div className="detail-skeleton">
            <div />
            <div />
          </div>
        ) : activeTab === "store" ? (
          /* 商城商品网格 */
          <section className="points-store-grid">
            {products.map((item) => {
              const canAfford = balance >= item.points;
              return (
                <div key={item.id} className="store-product-card">
                  <div className="product-media-frame">
                    {item.imageUrl ? (
                      <img src={item.imageUrl} alt={item.name} className="product-img" />
                    ) : (
                      <div className="product-emoji-placeholder">
                        <span className="product-emoji">{item.emoji || "🎁"}</span>
                      </div>
                    )}
                    <span className="product-points-tag">
                      🪙 {item.points} 积分
                    </span>
                  </div>

                  <div className="product-info">
                    <h3 className="product-name">{item.name}</h3>
                    <p className="product-desc">{item.description || "社区专属纪念周边实物礼品"}</p>

                    <div className="product-meta-row">
                      <span className="product-redeemed">已兑换 {item.redeemedCount || 0} 件</span>

                      {isGuest ? (
                        <button
                          type="button"
                          className="product-action-btn guest"
                          onClick={() => router.push(`/login?mode=register&next=${encodeURIComponent("/points")}`)}
                        >
                          注册后兑换
                        </button>
                      ) : canAfford ? (
                        <button
                          type="button"
                          className="product-action-btn primary"
                          onClick={() => setSelectedProduct(item)}
                        >
                          立即兑换
                        </button>
                      ) : (
                        <button
                          type="button"
                          className="product-action-btn disabled"
                          disabled
                        >
                          积分不足 (差 {item.points - balance})
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </section>
        ) : activeTab === "orders" ? (
          /* 兑换订单列表 */
          <section className="points-orders-section">
            {orders.length > 0 ? (
              <div className="orders-list">
                {orders.map((order) => {
                  const isApproved = order.status === "approved";
                  const canEditShipping =
                    isApproved &&
                    (order.fulfillmentStatus === "awaiting_address" ||
                      order.fulfillmentStatus === "ready_to_ship");

                  return (
                    <div key={order.id} className="order-card">
                      <div className="order-header">
                        <div className="order-title-box">
                          <strong className="order-prod-name">{order.productName}</strong>
                          <span className="order-date">{relativeTime(order.createdAt)} 兑换</span>
                        </div>
                        <div className="order-status-badge-wrap">
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
                        <div className="order-points-deduct">消耗: <strong>{order.points} 积分</strong></div>

                        {/* 物流发货信息展示 */}
                        {order.shipping?.trackingNo && (
                          <div className="order-tracking-info">
                            <span className="carrier-name">{order.shipping.carrier || "顺丰速运"}</span>
                            <span className="tracking-num">单号：{order.shipping.trackingNo}</span>
                          </div>
                        )}

                        {/* 已有地址摘要 */}
                        {order.shipping?.recipientName && (
                          <div className="order-address-summary">
                            收件人：{order.shipping.recipientName} ({order.shipping.phone}) <br />
                            地址：{order.shipping.province}{order.shipping.city}{order.shipping.district}{order.shipping.addressDetail}
                          </div>
                        )}

                        {/* 填写/修改收货地址入口 */}
                        {canEditShipping && (
                          <button
                            type="button"
                            className="order-shipping-edit-btn"
                            onClick={() => handleOpenShipping(order)}
                          >
                            <Icon name="edit" size={14} />
                            <span>{order.shipping?.recipientName ? "修改收货地址" : "填写收货地址"}</span>
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : (
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
                  onClick={() => setActiveTab("store")}
                >
                  去逛商城
                </button>
              </div>
            )}
          </section>
        ) : (
          /* 积分收支明细 */
          <section className="points-tx-section">
            {transactions.length > 0 ? (
              <div className="transactions-list">
                {transactions.map((tx) => (
                  <div key={tx.id} className="tx-row">
                    <div className="tx-main">
                      <strong className="tx-reason">{tx.reason || tx.source}</strong>
                      <span className="tx-time">{relativeTime(tx.createdAt)}</span>
                    </div>
                    <div className="tx-amount-col">
                      <span className={`tx-delta ${tx.delta > 0 ? "positive" : "negative"}`}>
                        {tx.delta > 0 ? `+${tx.delta}` : tx.delta}
                      </span>
                      <small className="tx-after">余额: {tx.balanceAfter}</small>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="workbench-empty-compact">
                <div className="workbench-empty-icon">
                  <Icon name="history" size={20} />
                </div>
                <div className="workbench-empty-text">
                  <h3>暂无积分流水明细</h3>
                  <p>积极发帖、互动交流即可累积积分</p>
                </div>
                <Link href="/" className="workbench-empty-action">
                  去逛社区
                </Link>
              </div>
            )}
          </section>
        )}

        {/* 兑换确认弹窗 */}
        {selectedProduct && (
          <div className="modal-backdrop" onClick={() => setSelectedProduct(null)}>
            <div className="modal-card" onClick={(e) => e.stopPropagation()}>
              <div className="modal-head">
                <h3>确认兑换礼品</h3>
                <button
                  type="button"
                  className="modal-close"
                  onClick={() => setSelectedProduct(null)}
                >
                  <Icon name="close" size={18} />
                </button>
              </div>
              <div className="modal-body">
                <p>
                  确认扣除 <strong>{selectedProduct.points} 积分</strong> 兑换「
                  <strong>{selectedProduct.name}</strong>」吗？
                </p>
                <p className="modal-footnote">
                  提交后将扣除对应积分并进入后台审核，审核通过后即可填写寄送地址。
                </p>
              </div>
              <div className="modal-actions">
                <button
                  type="button"
                  className="outline-button"
                  onClick={() => setSelectedProduct(null)}
                >
                  取消
                </button>
                <button
                  type="button"
                  className="primary-button"
                  disabled={redeemBusy}
                  onClick={handleConfirmRedeem}
                >
                  {redeemBusy ? "正在提交…" : "确认兑换"}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* 收货地址填写弹窗 */}
        {shippingOrder && (
          <div className="modal-backdrop" onClick={() => setShippingOrder(null)}>
            <div className="modal-card" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 460 }}>
              <div className="modal-head">
                <h3>填写收货地址</h3>
                <button
                  type="button"
                  className="modal-close"
                  onClick={() => setShippingOrder(null)}
                >
                  <Icon name="close" size={18} />
                </button>
              </div>
              <form onSubmit={handleSubmitShipping} className="modal-form">
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

                {shippingError && <div className="form-error">{shippingError}</div>}

                <div className="modal-actions">
                  <button
                    type="button"
                    className="outline-button"
                    onClick={() => setShippingOrder(null)}
                  >
                    取消
                  </button>
                  <button
                    type="submit"
                    className="primary-button"
                    disabled={shippingBusy}
                  >
                    {shippingBusy ? "正在保存…" : "保存收货地址"}
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}

        {/* 规则说明弹窗 */}
        {rulesOpen && (
          <div className="modal-backdrop" onClick={() => setRulesOpen(false)}>
            <div className="modal-card" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 480 }}>
              <div className="modal-head">
                <h3>社区积分规则说明</h3>
                <button
                  type="button"
                  className="modal-close"
                  onClick={() => setRulesOpen(false)}
                >
                  <Icon name="close" size={18} />
                </button>
              </div>
              <div className="modal-body rules-body">
                <h4>如何获取积分？</h4>
                <ul>
                  <li><strong>每日登录/签到</strong>：每日首次访问社区获得 <strong>+5 积分</strong>。</li>
                  <li><strong>发布优质内容</strong>：每发布一篇有效帖子获得 <strong>+10 积分</strong>（每日上限 30 积分）。</li>
                  <li><strong>发表互动评论</strong>：发表建设性回复获得 <strong>+2 积分</strong>（每日上限 20 积分）。</li>
                  <li><strong>收获同好点赞</strong>：你的帖子或评论每获得 1 个点赞获得 <strong>+1 积分</strong>。</li>
                </ul>

                <h4>兑换与发货规则</h4>
                <ul>
                  <li>积分兑换提交后进入后台安全风控与审核。</li>
                  <li>审核通过后，在「兑换记录」中填写收货地址，我们将在 3-5 个工作日内安排快递寄送并更新单号。</li>
                  <li>严禁使用脚本或违规刷分，一经核实将扣减违规积分或冻结兑换权限。</li>
                </ul>
              </div>
              <div className="modal-actions">
                <button
                  type="button"
                  className="primary-button"
                  onClick={() => setRulesOpen(false)}
                >
                  我知道了
                </button>
              </div>
            </div>
          </div>
        )}
      </main>

      <AppDownloadBanner />
      <BottomNav activeNav="profile" />
    </>
  );
}
