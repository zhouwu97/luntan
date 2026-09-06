"use client";

import { useCallback, useEffect, useState } from "react";
import { getMyPointsDetail } from "../../../lib/api/forum";
import { formatError } from "../../../lib/format";
import type { PointTransaction } from "../../../types/forum";

export interface UsePointsReturn {
  balance: number;
  reservedPoints: number;
  availablePoints: number;
  transactions: PointTransaction[];
  loading: boolean;
  error: string;
  reload: () => Promise<void>;
  onOrderSubmitted: (pointsCost: number) => void;
}

export function usePoints(ready: boolean, loggedIn: boolean): UsePointsReturn {
  const [balance, setBalance] = useState(0);
  const [reservedPoints, setReservedPoints] = useState(0);
  const [availablePoints, setAvailablePoints] = useState(0);
  const [transactions, setTransactions] = useState<PointTransaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const fetchPoints = useCallback(async () => {
    if (!loggedIn) {
      setBalance(0);
      setReservedPoints(0);
      setAvailablePoints(0);
      setTransactions([]);
      setLoading(false);
      setError("");
      return;
    }
    setLoading(true);
    setError("");
    try {
      const data = await getMyPointsDetail();
      setBalance(data.balance);
      setReservedPoints(data.reservedPoints);
      setAvailablePoints(data.availablePoints);
      setTransactions(data.transactions);
    } catch (err) {
      setError(formatError(err, "积分数据暂时无法加载"));
    } finally {
      setLoading(false);
    }
  }, [loggedIn]);

  useEffect(() => {
    if (!ready) return;
    void fetchPoints();
  }, [ready, fetchPoints]);

  const onOrderSubmitted = useCallback((pointsCost: number) => {
    // Sprint 1: 提交申请不扣真实 balance，只把占用积分增加，可用积分减少
    setReservedPoints((prev) => prev + pointsCost);
    setAvailablePoints((prev) => Math.max(0, prev - pointsCost));
  }, []);

  return {
    balance,
    reservedPoints,
    availablePoints,
    transactions,
    loading,
    error,
    reload: fetchPoints,
    onOrderSubmitted,
  };
}
