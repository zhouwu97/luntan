"use client";

import Link from "next/link";
import { Icon } from "../../../components/icons";
import { relativeTime } from "../../../lib/format";
import type { PointTransaction } from "../../../types/forum";

interface TransactionListProps {
  transactions: PointTransaction[];
  loading: boolean;
  error: string;
  onReload: () => void;
}

export function TransactionList({
  transactions,
  loading,
  error,
  onReload,
}: TransactionListProps) {
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
          重新加载明细
        </button>
      </div>
    );
  }

  if (transactions.length === 0) {
    return (
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
    );
  }

  return (
    <section className="points-tx-section">
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
    </section>
  );
}
