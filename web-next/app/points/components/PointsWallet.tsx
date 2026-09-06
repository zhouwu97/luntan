"use client";

import { useRouter } from "next/navigation";
import { Icon } from "../../../components/icons";
import { compactCount } from "../../../lib/format";

interface PointsWalletProps {
  balance: number;
  reservedPoints: number;
  availablePoints: number;
  loading: boolean;
  error: string;
  isGuest: boolean;
  onOpenRules: () => void;
  onReload: () => void;
}

export function PointsWallet({
  balance,
  reservedPoints,
  availablePoints,
  loading,
  error,
  isGuest,
  onOpenRules,
  onReload,
}: PointsWalletProps) {
  const router = useRouter();

  return (
    <section className="points-hero-card">
      <div className="points-hero-left">
        <span className="points-hero-label">我的积分</span>
        <div className="points-hero-val-row">
          <strong className="points-hero-number">
            {loading ? "…" : compactCount(balance)}
          </strong>
          <span className="points-unit">PTS</span>
        </div>

        {/* 三值显示：当前可兑换 vs 审核中占用 */}
        <div
          style={{
            display: "flex",
            gap: 24,
            marginTop: 10,
            paddingTop: 10,
            borderTop: "1px solid rgba(255, 255, 255, 0.2)",
          }}
        >
          <div style={{ display: "flex", flexDirection: "column" }}>
            <span style={{ fontSize: 12, opacity: 0.85 }}>当前可兑换</span>
            <strong style={{ fontSize: 18, fontWeight: 800, marginTop: 2 }}>
              {loading ? "…" : compactCount(availablePoints)}
            </strong>
          </div>
          <div style={{ display: "flex", flexDirection: "column" }}>
            <span style={{ fontSize: 12, opacity: 0.85 }}>审核中占用</span>
            <strong style={{ fontSize: 18, fontWeight: 800, marginTop: 2 }}>
              {loading ? "…" : compactCount(reservedPoints)}
            </strong>
          </div>
        </div>

        {error && (
          <div
            style={{
              marginTop: 12,
              padding: "6px 12px",
              background: "rgba(239, 68, 68, 0.2)",
              borderRadius: 8,
              border: "1px solid rgba(239, 68, 68, 0.4)",
              fontSize: 12,
              display: "flex",
              alignItems: "center",
              gap: 8,
            }}
          >
            <span>{error}</span>
            <button
              type="button"
              onClick={onReload}
              style={{
                background: "transparent",
                border: 0,
                color: "#fca5a5",
                textDecoration: "underline",
                cursor: "pointer",
                fontWeight: 600,
                fontSize: 12,
              }}
            >
              重新加载
            </button>
          </div>
        )}
      </div>

      <div className="points-hero-right">
        <button
          type="button"
          className="points-rule-btn"
          onClick={onOpenRules}
        >
          <Icon name="info" size={15} />
          <span>积分规则说明</span>
        </button>
        {isGuest && (
          <button
            type="button"
            className="points-upgrade-btn"
            onClick={() =>
              router.push(`/login?mode=register&next=${encodeURIComponent("/points")}`)
            }
          >
            注册升级账号
          </button>
        )}
      </div>
    </section>
  );
}
