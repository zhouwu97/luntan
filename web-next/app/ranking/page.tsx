"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { SiteHeader } from "../../components/site-header";
import { Icon } from "../../components/icons";
import { getRankingToys } from "../../lib/api/forum";
import { compactCount, formatError } from "../../lib/format";
import type { RankingToy } from "../../types/forum";

export default function RankingPage() {
  const [items, setItems] = useState<RankingToy[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    void getRankingToys()
      .then((nextItems) => {
        if (active) setItems(nextItems);
      })
      .catch((requestError: unknown) => {
        if (active) setError(formatError(requestError, "榜单暂时无法加载，请稍后再试"));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <section className="feature-page ranking-page">
          <div className="feature-hero">
            <div>
              <span className="feature-kicker"><Icon name="trophy" size={16} /> 北邮酱榜单</span>
              <h1>本周好物榜</h1>
              <p>看看大家最近在关注什么，找到适合自己的那一款。</p>
            </div>
            <Link href="/?sort=hot" className="outline-button feature-back">回到社区</Link>
          </div>
          {error && <div className="data-note" role="status">{error}</div>}
          {loading ? (
            <div className="ranking-grid" aria-label="榜单加载中"><div className="ranking-skeleton" /><div className="ranking-skeleton" /><div className="ranking-skeleton" /></div>
          ) : items.length ? (
            <div className="ranking-grid">
              {items.map((item) => <RankingCard key={item.id} item={item} />)}
            </div>
          ) : (
            <div className="empty-state feature-empty"><span className="empty-icon"><Icon name="trophy" size={24} /></span><h2>榜单正在准备中</h2><p>先去社区看看大家最近的真实分享吧。</p><Link href="/" className="primary-link">浏览帖子</Link></div>
          )}
        </section>
      </main>
    </>
  );
}

function RankingCard({ item }: { item: RankingToy }) {
  return (
    <article className="ranking-card">
      <div className={`ranking-card-rank rank-${item.rank}`}>{item.rank}</div>
      <div className="ranking-cover">
        {item.coverUrl ? <img src={item.coverUrl} alt="" loading="lazy" /> : <Icon name="box" size={30} />}
      </div>
      <div className="ranking-card-copy">
        <div className="ranking-card-title"><h2>{item.name}</h2>{item.score > 0 && <strong>{item.score.toFixed(1)}</strong>}</div>
        {item.merchant && <p className="ranking-merchant">{item.merchant}</p>}
        <p className="ranking-description">{item.description || "暂无产品介绍"}</p>
        <div className="ranking-card-meta"><span>{compactCount(item.wantCount)} 人想要</span><span>{compactCount(item.ratingCount)} 条评价</span></div>
        {item.tags.length > 0 && <div className="ranking-tags">{item.tags.slice(0, 3).map((tag) => <span key={tag}>{tag}</span>)}</div>}
      </div>
    </article>
  );
}
