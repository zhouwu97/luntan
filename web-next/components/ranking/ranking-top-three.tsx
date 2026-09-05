"use client";

import Link from "next/link";
import { Icon } from "../icons";
import styles from "../../app/ranking/ranking.module.css";
import type { RankingToy } from "../../types/forum";

interface RankingTopThreeProps {
  top1?: RankingToy;
  top2?: RankingToy;
  top3?: RankingToy;
  returnPath: string;
  scoreText: (score?: number) => string;
  compactCount: (value: number) => string;
}

export function RankingTopThree({
  top1,
  top2,
  top3,
  returnPath,
  scoreText,
  compactCount,
}: RankingTopThreeProps) {
  if (!top1 && !top2 && !top3) return null;

  return (
    <div className="ranking-top-three-wrapper" data-testid="ranking-top-three">
      {/* 1. TOP 1 深色特色卡片 */}
      {top1 && (
        <Link
          href={`/ranking/${encodeURIComponent(top1.id)}?from=${encodeURIComponent(returnPath)}`}
          className={styles.top1Link}
          data-testid="ranking-top1-link"
        >
          <article className={styles.top1Card}>
            <div className={styles.top1CrownBadge}>
              <Icon name="trophy" size={13} />
              <span>本周冠军</span>
            </div>
            <div className={styles.top1Num}>01</div>

            <div className={styles.top1ImgBox}>
              <img
                src={top1.coverUrl || top1.heroUrl || "/default-avatar.webp"}
                alt={top1.name}
              />
            </div>

            <div className={styles.top1Details}>
              <div className={styles.top1TitleLine}>
                <h2 className={styles.top1Title}>{top1.name}</h2>
                <div className={styles.top1ScoreVal}>
                  <strong>{scoreText(top1.score)}</strong>
                  <small>分</small>
                </div>
              </div>

              <div className={styles.top1Tags}>
                <span className={styles.top1Merchant}>{top1.merchant || "CUP"}</span>
                {top1.tags.slice(0, 3).map((tag) => (
                  <span key={tag} className={styles.top1Tag}>
                    #{tag}
                  </span>
                ))}
              </div>

              <p className={styles.top1Desc}>
                {top1.description || "热门精选，玩家高口碑推荐好物"}
              </p>

              <div className={styles.top1Kpis}>
                <span>
                  <b>{top1.ratingCount || 0}</b> 篇测评
                </span>
                <span>·</span>
                <span>
                  <b>{compactCount(top1.wantCount || 0)}</b> 人想要
                </span>
              </div>
            </div>
          </article>
        </Link>
      )}

      {/* 2. TOP 2 / TOP 3 双列并排 */}
      {(top2 || top3) && (
        <div className={styles.top23Grid} style={{ marginTop: 14 }} data-testid="ranking-top23-grid">
          {top2 && (
            <Link
              href={`/ranking/${encodeURIComponent(top2.id)}?from=${encodeURIComponent(returnPath)}`}
              className={styles.top23Link}
              data-testid="ranking-top2-link"
            >
              <article className={styles.top23Card}>
                <div className={`${styles.top23Badge} ${styles.rank2}`}>02</div>
                <div className={styles.top23Thumb}>
                  <img
                    src={top2.coverUrl || top2.heroUrl || "/default-avatar.webp"}
                    alt={top2.name}
                  />
                </div>
                <div className={styles.top23Info}>
                  <h3 className={styles.top23Name}>{top2.name}</h3>
                  <div className={styles.top23Meta}>
                    <span>{top2.merchant || "CUP"}</span>
                    <span>·</span>
                    <span>{top2.ratingCount || 0} 测评</span>
                  </div>
                  <div className={styles.top23Score}>
                    <strong>{scoreText(top2.score)}</strong>
                    <small>分</small>
                  </div>
                </div>
              </article>
            </Link>
          )}

          {top3 && (
            <Link
              href={`/ranking/${encodeURIComponent(top3.id)}?from=${encodeURIComponent(returnPath)}`}
              className={styles.top23Link}
              data-testid="ranking-top3-link"
            >
              <article className={styles.top23Card}>
                <div className={`${styles.top23Badge} ${styles.rank3}`}>03</div>
                <div className={styles.top23Thumb}>
                  <img
                    src={top3.coverUrl || top3.heroUrl || "/default-avatar.webp"}
                    alt={top3.name}
                  />
                </div>
                <div className={styles.top23Info}>
                  <h3 className={styles.top23Name}>{top3.name}</h3>
                  <div className={styles.top23Meta}>
                    <span>{top3.merchant || "CUP"}</span>
                    <span>·</span>
                    <span>{top3.ratingCount || 0} 测评</span>
                  </div>
                  <div className={styles.top23Score}>
                    <strong>{scoreText(top3.score)}</strong>
                    <small>分</small>
                  </div>
                </div>
              </article>
            </Link>
          )}
        </div>
      )}
    </div>
  );
}
