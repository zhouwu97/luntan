"use client";

import { useCallback, useEffect, useState } from "react";
import { completeMyStoreOrder, getMyStoreOrders } from "../../../lib/api/forum";
import { formatError } from "../../../lib/format";
import type { StoreOrder } from "../../../types/forum";

export interface UseStoreOrdersReturn {
  orders: StoreOrder[];
  loading: boolean;
  loadingMore: boolean;
  hasMore: boolean;
  nextCursor?: string;
  error: string;
  loadMoreError: string;
  reload: () => Promise<void>;
  loadMore: () => Promise<void>;
  addOrder: (order: StoreOrder) => void;
  updateOrder: (order: StoreOrder) => void;
  completeOrder: (orderId: string) => Promise<StoreOrder>;
}

export function useStoreOrders(ready: boolean, loggedIn: boolean): UseStoreOrdersReturn {
  const [orders, setOrders] = useState<StoreOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const [nextCursor, setNextCursor] = useState<string | undefined>();
  const [error, setError] = useState("");
  const [loadMoreError, setLoadMoreError] = useState("");

  const fetchOrders = useCallback(async () => {
    if (!loggedIn) {
      setOrders([]);
      setHasMore(false);
      setNextCursor(undefined);
      setLoading(false);
      setError("");
      return;
    }
    setLoading(true);
    setError("");
    setLoadMoreError("");
    try {
      const page = await getMyStoreOrders(undefined, 20);
      setOrders(page.items);
      setNextCursor(page.nextCursor);
      setHasMore(page.hasMore);
    } catch (err) {
      setError(formatError(err, "兑换记录暂时无法加载"));
    } finally {
      setLoading(false);
    }
  }, [loggedIn]);

  useEffect(() => {
    if (!ready) return;
    void fetchOrders();
  }, [ready, fetchOrders]);

  const loadMore = useCallback(async () => {
    if (!hasMore || !nextCursor || loadingMore) return;
    setLoadingMore(true);
    setLoadMoreError("");
    try {
      const page = await getMyStoreOrders(nextCursor, 20);
      setOrders((prev) => {
        const known = new Set(prev.map((x) => x.id));
        const newItems = page.items.filter((x) => !known.has(x.id));
        return [...prev, ...newItems];
      });
      setNextCursor(page.nextCursor);
      setHasMore(page.hasMore);
    } catch (err) {
      setLoadMoreError(formatError(err, "加载更多订单失败，点击重试"));
    } finally {
      setLoadingMore(false);
    }
  }, [hasMore, nextCursor, loadingMore]);

  const addOrder = useCallback((order: StoreOrder) => {
    setOrders((prev) => {
      const known = new Set(prev.map((x) => x.id));
      if (known.has(order.id)) {
        return prev.map((x) => (x.id === order.id ? order : x));
      }
      return [order, ...prev];
    });
  }, []);

  const updateOrder = useCallback((order: StoreOrder) => {
    setOrders((prev) => prev.map((x) => (x.id === order.id ? order : x)));
  }, []);

  const completeOrder = useCallback(async (orderId: string): Promise<StoreOrder> => {
    const updated = await completeMyStoreOrder(orderId);
    setOrders((prev) => prev.map((x) => (x.id === updated.id ? updated : x)));
    return updated;
  }, []);

  return {
    orders,
    loading,
    loadingMore,
    hasMore,
    nextCursor,
    error,
    loadMoreError,
    reload: fetchOrders,
    loadMore,
    addOrder,
    updateOrder,
    completeOrder,
  };
}
