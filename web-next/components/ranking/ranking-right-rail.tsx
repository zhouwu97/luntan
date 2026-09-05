"use client";

import Link from "next/link";
import { Icon } from "../icons";
import styles from "../../app/ranking/ranking.module.css";
import type { RankingToy } from "../../types/forum";

interface RankingRightRailProps {
  weeklyTop: RankingToy;
  returnPath: string;
  scoreText: (score?: number) => string;
  compactCount: (value: number) => string;
  onOpenRules?: () => void;
}

export function RankingRightRail({
  weeklyTop,
  returnPath,
  scoreText,
  compactCount,
  onOpenRules,
}: RankingRightRailProps) {
  return (
    <div className="ranking-right-rail-inner" data-testid="ranking-right-rail-inner">
      <div className={styles.championCard}>
        <div className={styles.championKicker}>
          <Icon name="trophy" size={13} />
          <span>本周总榜冠军</span>
        </div>

        <Link
          href={`/ranking/${encodeURIComponent(weeklyTop.id)}?from=${encodeURIComponent(returnPath)}`}
          style={{ textDecoration: "none", color: "inherit", display: "block" }}
        >
          <div className={styles.championThumb}>
            <img
              src={weeklyTop.coverUrl || weeklyTop.heroUrl || "/default-avatar.webp"}
              alt={weeklyTop.name}
            />
          </div>

          <h4 className={styles.championTitle}>{weeklyTop.name}</h4>

          <div className={styles.top1ScoreVal} style={{ marginBottom: 6 }}>
            <strong style={{ fontSize: 20 }}>{scoreText(weeklyTop.score)}</strong>
            <small style={{ color: "#ffd33d" }}>分</small>
          </div>

          <div className={styles.championMeta}>
            <span>{weeklyTop.ratingCount || 0} 篇测评</span>
            <span> · </span>
            <span>{compactCount(weeklyTop.wantCount || 0)} 想要</span>
          </div>
        </Link>
      </div>

      {onOpenRules ? (
        <div
          className={styles.championCard}
          style={{ marginTop: 14, cursor: "pointer", background: "#f8fafc" }}
          onClick={onOpenRules}
          data-testid="ranking-rules-card"
        >
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 6, color: "#2563eb", fontWeight: 800, fontSize: 13 }}>
              <Icon name="info" size={14} />
              <span>榜单评选公约</span>
            </div>
            <Icon name="chevron-right" size={14} style={{ color: "#94a3b8" }} />
          </div>
          <p style={{ margin: "8px 0 0", fontSize: 12, color: "#64748b", lineHeight: 1.6 }}>
            真实同好体验打分，结合测评互动加权计算，杜绝商业刷榜。
          </p>
        </div>
      ) : null}
    </div>
  );
}
