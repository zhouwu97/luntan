"use client";

import Link from "next/link";
import styles from "../../app/ranking/ranking.module.css";
import type { RankingToy } from "../../types/forum";

interface RankingListProps {
  items: RankingToy[];
  startIndex?: number;
  returnPath: string;
  scoreText: (score?: number) => string;
  compactCount: (value: number) => string;
}

export function RankingList({
  items,
  startIndex = 4,
  returnPath,
  scoreText,
  compactCount,
}: RankingListProps) {
  if (!items || items.length === 0) return null;

  return (
    <div className={styles.listContainer} data-testid="ranking-list-container">
      {items.map((item, index) => {
        const rankNum = (startIndex + index).toString().padStart(2, "0");
        return (
          <Link
            key={item.id}
            href={`/ranking/${encodeURIComponent(item.id)}?from=${encodeURIComponent(returnPath)}`}
            className={styles.rowLink}
            data-testid={`ranking-row-link-${rankNum}`}
          >
            <article className={styles.horizontalRow} data-testid={`ranking-row-${rankNum}`}>
              <div className={styles.rowNum}>{rankNum}</div>
              <div className={styles.rowThumb}>
                <img
                  src={item.coverUrl || item.heroUrl || "/default-avatar.webp"}
                  alt={item.name}
                />
              </div>
              <div className={styles.rowContent}>
                <h4 className={styles.rowTitle}>{item.name}</h4>
                <div className={styles.rowMeta}>
                  <span>{item.merchant || "CUP"}</span>
                  <span>·</span>
                  <span>{item.ratingCount || 0} 测评</span>
                  <span>·</span>
                  <span>{compactCount(item.wantCount || 0)} 想要</span>
                </div>
              </div>
              <div className={styles.rowScore}>
                <strong>{scoreText(item.score)}</strong>
                <small>分</small>
              </div>
            </article>
          </Link>
        );
      })}
    </div>
  );
}
