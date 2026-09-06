"use client";

import Link from "next/link";
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { SiteHeader } from "../../components/site-header";
import { BottomNav } from "../../components/bottom-nav";
import { AppDownloadBanner } from "../../components/app-download-banner";
import { Icon } from "../../components/icons";
import { useSession } from "../../components/session-provider";
import { useToast } from "../../components/toast-context";
import { createStoreOrder, getStoreProducts } from "../../lib/api/forum";
import { formatError } from "../../lib/format";
import type { StoreOrder, StoreProduct } from "../../types/forum";
import { usePoints } from "./hooks/usePoints";
import { useStoreOrders } from "./hooks/useStoreOrders";
import { PointsWallet } from "./components/PointsWallet";
import { PointsTabs, type PointsTab } from "./components/PointsTabs";
import { StoreProductGrid } from "./components/StoreProductGrid";
import { OrderList } from "./components/OrderList";
import { TransactionList } from "./components/TransactionList";
import { RedeemDialog } from "./components/RedeemDialog";
import { ShippingDialog } from "./components/ShippingDialog";
import { PointsRulesDialog } from "./components/PointsRulesDialog";

function PointsCenterContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { user, ready, isGuest, isRegistered } = useSession();
  const { showToast } = useToast();

  const tabParam = searchParams.get("tab") as PointsTab | null;
  const orderParam = searchParams.get("order");

  const [activeTab, setActiveTab] = useState<PointsTab>(() => {
    if (orderParam) return "orders";
    if (tabParam === "orders" || tabParam === "transactions") return tabParam;
    return "store";
  });

  // 商品数据与状态（独立管理，禁止静默吞错误）
  const [products, setProducts] = useState<StoreProduct[]>([]);
  const [productsLoading, setProductsLoading] = useState(true);
  const [productsError, setProductsError] = useState("");

  const loadProducts = useCallback(async () => {
    setProductsLoading(true);
    setProductsError("");
    try {
      const list = await getStoreProducts();
      setProducts(list);
    } catch (err) {
      setProductsError(formatError(err, "商品列表暂时无法加载"));
    } finally {
      setProductsLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadProducts();
  }, [loadProducts]);

  // 积分与明细 Hook
  const {
    balance,
    reservedPoints,
    availablePoints,
    transactions,
    loading: pointsLoading,
    error: pointsError,
    reload: reloadPoints,
    onOrderSubmitted,
  } = usePoints(ready, Boolean(user));

  // 兑换订单 Hook
  const {
    orders,
    loading: ordersLoading,
    loadingMore: ordersLoadingMore,
    hasMore: ordersHasMore,
    nextCursor: ordersNextCursor,
    error: ordersError,
    loadMoreError: ordersLoadMoreError,
    reload: reloadOrders,
    loadMore: loadMoreOrders,
    addOrder,
    updateOrder,
    completeOrder,
  } = useStoreOrders(ready, Boolean(user));

  // 弹窗状态
  const [rulesOpen, setRulesOpen] = useState(false);
  const [selectedProduct, setSelectedProduct] = useState<StoreProduct | null>(null);
  const [redeemBusy, setRedeemBusy] = useState(false);
  const [shippingOrder, setShippingOrder] = useState<StoreOrder | null>(null);

  // 确认收货二次确认弹窗
  const [orderToComplete, setOrderToComplete] = useState<StoreOrder | null>(null);
  const [completeBusy, setCompleteBusy] = useState(false);

  // Sprint 3: 追踪是否已根据 deep link 自动弹窗
  const autoOpenedOrderRef = useRef<string | null>(null);

  useEffect(() => {
    if (!orderParam || orders.length === 0) return;
    if (autoOpenedOrderRef.current === orderParam) return;

    const matched = orders.find((o) => o.id === orderParam);
    if (matched) {
      setActiveTab("orders");
      autoOpenedOrderRef.current = orderParam;
      if (matched.status === "approved" && matched.fulfillmentStatus === "awaiting_address") {
        setShippingOrder(matched);
      }
    }
  }, [orderParam, orders]);

  // 兑换提交（Sprint 1: 审核通过才扣分，此处不扣真实 balance）
  async function handleConfirmRedeem() {
    if (!selectedProduct) return;
    if (!isRegistered) {
      router.push(`/login?mode=register&next=${encodeURIComponent("/points")}`);
      return;
    }

    setRedeemBusy(true);
    try {
      const order = await createStoreOrder(selectedProduct.id);
      showToast(`兑换申请已提交，等待管理员审核！`);
      onOrderSubmitted(selectedProduct.points);
      addOrder(order);
      setSelectedProduct(null);
      setActiveTab("orders");
    } catch (err) {
      showToast(formatError(err, "兑换提交失败，请稍后再试"));
    } finally {
      setRedeemBusy(false);
    }
  }

  // 确认收货操作（Sprint 9）
  async function handleConfirmReceipt() {
    if (!orderToComplete) return;
    setCompleteBusy(true);
    try {
      await completeOrder(orderToComplete.id);
      showToast("已确认收货，订单完成！");
      setOrderToComplete(null);
    } catch (err) {
      showToast(formatError(err, "确认收货失败，请稍后重试"));
    } finally {
      setCompleteBusy(false);
    }
  }

  return (
    <>
      <SiteHeader />

      <main
        className="page-frame points-page"
        style={{ maxWidth: 960, margin: "0 auto", padding: "20px 16px 80px" }}
      >
        <div className="points-top-nav">
          <Link href="/me" className="back-link">
            <Icon name="chevron-left" size={17} />
            <span>返回我的工作台</span>
          </Link>
        </div>

        {/* 积分总览卡片（三值展示） */}
        <PointsWallet
          balance={balance}
          reservedPoints={reservedPoints}
          availablePoints={availablePoints}
          loading={pointsLoading}
          error={pointsError}
          isGuest={isGuest}
          onOpenRules={() => setRulesOpen(true)}
          onReload={reloadPoints}
        />

        {/* 标签栏 */}
        <PointsTabs
          activeTab={activeTab}
          orderCount={orders.length}
          onTabChange={setActiveTab}
        />

        {/* 内容展示区 */}
        {activeTab === "store" ? (
          <StoreProductGrid
            products={products}
            loading={productsLoading}
            error={productsError}
            availablePoints={availablePoints}
            isGuest={isGuest}
            onRedeem={(prod) => setSelectedProduct(prod)}
            onGuestRegister={() =>
              router.push(`/login?mode=register&next=${encodeURIComponent("/points")}`)
            }
            onReload={loadProducts}
          />
        ) : activeTab === "orders" ? (
          <OrderList
            orders={orders}
            loading={ordersLoading}
            loadingMore={ordersLoadingMore}
            hasMore={ordersHasMore}
            nextCursor={ordersNextCursor}
            error={ordersError}
            loadMoreError={ordersLoadMoreError}
            highlightOrderId={orderParam || undefined}
            onOpenShipping={(order) => setShippingOrder(order)}
            onComplete={(order) => setOrderToComplete(order)}
            onReload={reloadOrders}
            onLoadMore={loadMoreOrders}
            onGoStore={() => setActiveTab("store")}
          />
        ) : (
          <TransactionList
            transactions={transactions}
            loading={pointsLoading}
            error={pointsError}
            onReload={reloadPoints}
          />
        )}

        {/* 申请兑换确认弹窗 */}
        <RedeemDialog
          product={selectedProduct}
          busy={redeemBusy}
          onClose={() => setSelectedProduct(null)}
          onConfirm={handleConfirmRedeem}
        />

        {/* 填写/修改收货地址弹窗 */}
        <ShippingDialog
          order={shippingOrder}
          onClose={() => setShippingOrder(null)}
          onSuccess={(updated) => {
            updateOrder(updated);
            showToast("收货地址已保存，待仓库发货！");
          }}
        />

        {/* 规则说明弹窗 */}
        <PointsRulesDialog
          open={rulesOpen}
          onClose={() => setRulesOpen(false)}
        />

        {/* 确认收货二次确认弹窗（Sprint 9） */}
        {orderToComplete && (
          <div className="modal-backdrop" onClick={() => setOrderToComplete(null)}>
            <div
              className="modal-card"
              role="dialog"
              aria-modal="true"
              aria-label="确认已收到周边礼品"
              onClick={(e) => e.stopPropagation()}
              style={{ maxWidth: 440 }}
            >
              <div className="modal-head">
                <h3>确认已收到周边礼品</h3>
                <button
                  type="button"
                  className="modal-close"
                  onClick={() => setOrderToComplete(null)}
                >
                  <Icon name="close" size={18} />
                </button>
              </div>
              <div className="modal-body">
                <p>
                  确认已经收到兑换商品「<strong>{orderToComplete.productName}</strong>」吗？
                </p>
                {orderToComplete.shipping?.trackingNo && (
                  <p style={{ fontSize: 13, color: "var(--text-soft)" }}>
                    物流配送：{orderToComplete.shipping.carrier || "快递"} {orderToComplete.shipping.trackingNo}
                  </p>
                )}
                <div
                  style={{
                    marginTop: 10,
                    padding: "10px 14px",
                    background: "#f0fdf4",
                    border: "1px solid #bbf7d0",
                    borderRadius: 8,
                    fontSize: 13,
                    color: "#166534",
                  }}
                >
                  确认收货后，该兑换订单将正式标记为已完成。
                </div>
              </div>
              <div className="modal-actions">
                <button
                  type="button"
                  className="outline-button"
                  disabled={completeBusy}
                  onClick={() => setOrderToComplete(null)}
                >
                  取消
                </button>
                <button
                  type="button"
                  className="primary-button"
                  disabled={completeBusy}
                  onClick={handleConfirmReceipt}
                >
                  {completeBusy ? "正在确认…" : "确认已收到"}
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

export default function PointsCenterPage() {
  return (
    <Suspense
      fallback={
        <>
          <SiteHeader />
          <main className="page-frame">
            <div className="detail-skeleton">
              <div />
              <div />
            </div>
          </main>
        </>
      }
    >
      <PointsCenterContent />
    </Suspense>
  );
}
