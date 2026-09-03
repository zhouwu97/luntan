"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Icon } from "./icons";
import { UserAvatar } from "./user-avatar";
import { getRankingView } from "../lib/api/forum";
import { compactCount, relativeTime } from "../lib/format";
import type { Post, RankingToy, SessionUser } from "../types/forum";

const RANK_NUM_COLORS = ["#f59e0b", "#94a3b8", "#d97706", "#64748b"];

export function DiscoveryRail({
  posts,
}: {
  posts: Post[];
  user: SessionUser | null;
  onLogin: () => void;
}) {
  const [rankingToys, setRankingToys] = useState<RankingToy[]>([]);
  const [weeklyTop, setWeeklyTop] = useState<RankingToy | undefined>();

  useEffect(() => {
    let mounted = true;
    getRankingView()
      .then((res) => {
        if (!mounted) return;
        if (res.items?.length) {
          setRankingToys(res.items.slice(0, 4));
          setWeeklyTop(res.weeklyTop || res.items[0]);
        }
      })
      .catch(() => {
        // Fallback gracefully if ranking API is quiet
      });
    return () => {
      mounted = false;
    };
  }, []);

  // 热门/刚刚讨论：按评论与最新活跃度排序
  const hotDiscussions = posts
    .slice()
    .sort((a, b) => b.commentCount + b.likeCount - (a.commentCount + a.likeCount))
    .slice(0, 4);

  const displayTop = weeklyTop || rankingToys[0];
  const otherRanks = displayTop ? rankingToys.filter((t) => t.id !== displayTop.id).slice(0, 3) : rankingToys.slice(1, 4);

  return (
    <aside className="desktop-right-rail" aria-label="社区右侧发现">
      {/* 热门/刚刚讨论 */}
      <section className="rail-panel">
        <div className="rail-head">
          <div className="rail-head-title">
            <span className="rail-head-icon orange"><Icon name="flame" size={16} /></span>
            <h3>热门讨论</h3>
          </div>
          <Link href="/?sort=hot" className="rail-head-link">
            更多 <Icon name="chevron-right" size={14} />
          </Link>
        </div>
        <div className="rail-discussion-list">
          {hotDiscussions.length > 0 ? (
            hotDiscussions.map((item) => (
              <Link
                key={item.id}
                href={`/post/${encodeURIComponent(item.id)}`}
                className="rail-discuss-item"
              >
                <div className="rail-discuss-main">
                  <span className="rail-discuss-tag">{item.community.name}</span>
                  <p className="rail-discuss-title">{item.title}</p>
                  <div className="rail-discuss-meta">
                    <UserAvatar
                      userId={item.author.id}
                      name={item.author.nickname}
                      url={item.author.avatarUrl}
                      size="small"
                    />
                    <span>{item.author.nickname}</span>
                    <span className="meta-dot">·</span>
                    <time dateTime={item.createdAt}>
                      {relativeTime(item.activityAt || item.createdAt)}
                    </time>
                  </div>
                </div>
                {item.commentCount > 0 && (
                  <span className="rail-discuss-badge">
                    <Icon name="message" size={12} />
                    {compactCount(item.commentCount)}
                  </span>
                )}
              </Link>
            ))
          ) : (
            <p className="empty-rail-hint">暂无最新讨论，快去发布吧</p>
          )}
        </div>
      </section>

      {/* 本周榜单精选 */}
      <section className="rail-panel">
        <div className="rail-head">
          <div className="rail-head-title">
            <span className="rail-head-icon blue"><Icon name="trophy" size={16} /></span>
            <h3>本周榜单</h3>
          </div>
          <Link href="/ranking" className="rail-head-link">
            进入榜单 <Icon name="chevron-right" size={14} />
          </Link>
        </div>

        {/* 榜首 Hero 卡片 */}
        {displayTop && (
          <Link href={`/ranking/${encodeURIComponent(displayTop.id)}`} className="rank-hero-celestial">
            <div className="rank-hero-top">
              <span className="rank-hero-kicker">本周榜首</span>
              <span className="rank-hero-score">{displayTop.score ? displayTop.score.toFixed(1) : "暂无评分"}</span>
            </div>
            <strong className="rank-hero-title">{displayTop.name}</strong>
            <div className="rank-hero-meta">
              <span>{displayTop.ratingCount ? `${displayTop.ratingCount} 篇测评` : "暂无测评"}</span>
              <span className="meta-dot">·</span>
              <span>{compactCount(displayTop.wantCount || 0)} 人想要</span>
            </div>
          </Link>
        )}

        {/* 第 2 ~ 4 名榜单行 */}
        <div className="rank-rows-list">
          {otherRanks.length > 0 ? (
            otherRanks.map((toy, index) => (
              <Link
                key={toy.id}
                href={`/ranking/${encodeURIComponent(toy.id)}`}
                className="rank-row-item"
              >
                <span className="rank-num" style={{ color: RANK_NUM_COLORS[index] }}>
                  {index + 2}
                </span>
                <span className="rank-thumb-frame">
                  {toy.coverUrl ? (
                    <img src={toy.coverUrl} alt={toy.name} className="rank-thumb-img" />
                  ) : (
                    <Icon name="box" size={20} className="rank-thumb-fallback" />
                  )}
                </span>
                <span className="rank-info">
                  <span className="rank-name">{toy.name}</span>
                  <span className="rank-meta">
                    {toy.category || "热门玩具"} · {toy.ratingCount || 0} 测评
                  </span>
                </span>
                <span className="rank-score-val">
                  {toy.score ? toy.score.toFixed(1) : "—"}
                </span>
              </Link>
            ))
          ) : (
            <p className="empty-rail-hint">正在更新本周榜单…</p>
          )}
        </div>
      </section>
    </aside>
  );
}
