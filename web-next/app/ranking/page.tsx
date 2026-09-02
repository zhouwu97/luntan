"use client";

import Link from "next/link";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "../../components/site-header";
import { Icon, type IconName } from "../../components/icons";
import { MediaImage } from "../../components/media-image";
import { getRankingView } from "../../lib/api/forum";
import { compactCount, formatError } from "../../lib/format";
import type { RankingToy } from "../../types/forum";

const rankingTabs = [
  { label: "综合热榜", key: "" },
  { label: "慢玩入门", key: "ENTRY" },
  { label: "进阶训练", key: "ADVANCED" },
  { label: "超高刺激", key: "HIGH" },
  { label: "榨汁玩具", key: "EXTREME" },
];

const rankingCategories: Array<{ label: string; key: string; icon: IconName }> = [
  { label: "飞机杯", key: "CUP", icon: "box" },
  { label: "小型臀模", key: "SMALL_MOLD", icon: "hanger" },
  { label: "大型臀模", key: "LARGE_MOLD", icon: "box" },
  { label: "半身腿模", key: "HALF_BODY", icon: "user" },
  { label: "润滑油", key: "LUBE", icon: "sparkle" },
];

function scoreText(score: number) {
  return score > 0 ? (score % 1 === 0 ? String(score) : score.toFixed(1)) : "—";
}

export default function RankingPage() {
  const router = useRouter();
  const [selectedTab, setSelectedTab] = useState(0);
  const [selectedCategory, setSelectedCategory] = useState("");
  const [query, setQuery] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [items, setItems] = useState<RankingToy[]>([]);
  const [weeklyTop, setWeeklyTop] = useState<RankingToy>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    void getRankingView(rankingTabs[selectedTab].key, selectedCategory)
      .then((view) => {
        if (!active) return;
        setItems(view.items);
        setWeeklyTop(view.weeklyTop);
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
  }, [selectedCategory, selectedTab]);

  const filteredItems = useMemo(() => {
    const normalized = searchQuery.trim().toLowerCase();
    if (!normalized) return items;
    return items.filter((item) => [item.name, item.merchant, item.description, ...item.tags].join(" ").toLowerCase().includes(normalized));
  }, [items, searchQuery]);

  const featuredItem = useMemo(() => {
    if (searchQuery.trim()) return undefined;
    return weeklyTop || filteredItems.find((item) => item.rank === 1) || filteredItems[0];
  }, [filteredItems, searchQuery, weeklyTop]);

  const listItems = featuredItem ? filteredItems.filter((item) => item.id !== featuredItem.id) : filteredItems;

  function submitSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSearchQuery(query);
  }

  function selectTab(index: number) {
    setSelectedTab(index);
    if (index > 0 && !selectedCategory) setSelectedCategory("CUP");
  }

  function selectCategory(key: string) {
    setSelectedCategory((current) => selectedTab === 0 && current === key ? "" : key);
  }

  return (
    <>
      <SiteHeader className="ranking-site-header" />
      <div className="ranking-mobile-header">
        <button type="button" className="ranking-mobile-back" aria-label="返回" onClick={() => router.back()}><Icon name="chevron-left" size={21} /></button>
        <form className="ranking-mobile-search" onSubmit={submitSearch} role="search">
          <Icon name="search" size={15} />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="搜索：魅魔、大雕王、慢玩..." aria-label="搜索榜单商品" />
        </form>
        <button type="button" className="ranking-mobile-add" aria-label="提交榜单商品" onClick={() => router.push("/login")}><Icon name="plus" size={17} /></button>
      </div>
      <main className="page-frame ranking-page-frame">
        <section className="feature-page ranking-page">
          <div className="feature-hero">
            <div>
              <span className="feature-kicker"><Icon name="trophy" size={16} /> 北邮酱榜单</span>
              <h1>本周好物榜</h1>
              <p>看看大家最近在关注什么，找到适合自己的那一款。</p>
            </div>
            <Link href="/?sort=hot" className="outline-button feature-back">回到社区</Link>
          </div>

          <div className="ranking-mobile-navigation">
            <nav className="ranking-tabs-mobile" aria-label="榜单类型">
              {rankingTabs.map((tab, index) => <button key={tab.key || "all"} type="button" className={selectedTab === index ? "active" : ""} onClick={() => selectTab(index)}>{tab.label}</button>)}
            </nav>
            <div className="ranking-categories-mobile" aria-label="商品分类">
              {rankingCategories.map((category) => <button key={category.key} type="button" className={`ranking-category-mobile${selectedCategory === category.key ? " active" : ""}`} onClick={() => selectCategory(category.key)}><Icon name={category.icon} size={21} /><span>{category.label}</span></button>)}
            </div>
          </div>

          {error && <div className="data-note" role="status">{error}</div>}
          {loading ? (
            <div className="ranking-grid" aria-label="榜单加载中"><div className="ranking-skeleton" /><div className="ranking-skeleton" /><div className="ranking-skeleton" /></div>
          ) : items.length ? (
            <>
              {featuredItem && <div className="ranking-desktop-featured"><RankingCard item={featuredItem} /></div>}
              {featuredItem && <RankingFeatured item={featuredItem} />}
              <div className="ranking-grid">
                {listItems.map((item) => <RankingCard key={item.id} item={item} />)}
              </div>
            </>
          ) : (
            <div className="empty-state feature-empty"><span className="empty-icon"><Icon name="trophy" size={24} /></span><h2>榜单正在准备中</h2><p>{searchQuery ? "未找到匹配的榜单商品。" : "先去社区看看大家最近的真实分享吧。"}</p><Link href="/" className="primary-link">浏览帖子</Link></div>
          )}
        </section>
      </main>
    </>
  );
}

function RankingFeatured({ item }: { item: RankingToy }) {
  return (
    <Link href={`/ranking/${encodeURIComponent(item.id)}`} className="ranking-featured-link">
      <article className="ranking-featured">
        <div className="ranking-featured-cover">
          <MediaImage sources={[item.heroUrl, item.coverUrl]} alt={item.name} loading="eager" />
          <span className="ranking-featured-label">No.1 本周霸权</span>
        </div>
        <div className="ranking-featured-copy">
          <div className="ranking-featured-title"><h2>{item.name}</h2><strong>{scoreText(item.score)}<small>分</small></strong></div>
          {item.tags.length > 0 && <div className="ranking-featured-tags">{item.tags.slice(0, 3).map((tag) => <span key={tag}>#{tag}</span>)}</div>}
        </div>
      </article>
    </Link>
  );
}

function RankingCard({ item }: { item: RankingToy }) {
  return (
    <Link href={`/ranking/${encodeURIComponent(item.id)}`} className="ranking-card-link">
      <article className="ranking-card">
        <div className={`ranking-card-rank rank-${item.rank}`}>{item.rank}</div>
        <div className="ranking-cover"><MediaImage sources={[item.coverUrl, item.heroUrl]} alt={item.name} /></div>
        <div className="ranking-card-copy">
          <div className="ranking-card-title"><h2>{item.name}</h2><strong>{scoreText(item.score)}</strong></div>
          {item.merchant && <p className="ranking-merchant">{item.merchant}</p>}
          <p className="ranking-description">{item.description || "暂无产品介绍"}</p>
          <div className="ranking-card-meta"><span>{compactCount(item.wantCount)} 人想要</span><span>{compactCount(item.ratingCount)} 条评价</span></div>
          {item.tags.length > 0 && <div className="ranking-tags">{item.tags.slice(0, 3).map((tag) => <span key={tag}>{tag}</span>)}</div>}
        </div>
        <div className="ranking-mobile-score">{scoreText(item.score)}<small>分</small></div>
      </article>
    </Link>
  );
}
