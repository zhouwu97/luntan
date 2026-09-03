"use client";

import Link from "next/link";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Icon, type IconName } from "../../components/icons";
import { MediaImage } from "../../components/media-image";
import { SiteHeader } from "../../components/site-header";
import { AppDownloadBanner } from "../../components/app-download-banner";
import { BottomNav } from "../../components/bottom-nav";
import { useSession } from "../../components/session-provider";
import { useToast } from "../../components/toast-context";
import { getRankingView } from "../../lib/api/forum";
import { compactCount, formatError } from "../../lib/format";
import type { RankingToy } from "../../types/forum";

const rankingTabs = [
  { key: "", label: "综合热榜" },
  { key: "BEGINNER", label: "慢玩入门" },
  { key: "ADVANCED", label: "进阶训练" },
  { key: "STIMULATING", label: "超高刺激" },
  { key: "EXTRACT", label: "榨汁玩具" },
];

const rankingCategories: Array<{ key: string; label: string; icon: IconName }> = [
  { key: "CUP", label: "飞机杯", icon: "box" },
  { key: "SMALL_HIPS", label: "小型臀模", icon: "sparkle" },
  { key: "LARGE_HIPS", label: "大型臀模", icon: "flame" },
  { key: "HALF_BODY", label: "半身腿模", icon: "hanger" },
  { key: "LUBE", label: "润滑油", icon: "calendar" },
];

function scoreText(score?: number) {
  if (typeof score !== "number" || Number.isNaN(score) || score <= 0) return "--";
  return score.toFixed(1);
}

export default function RankingPage() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { user } = useSession();
  const { showToast } = useToast();

  const tabParam = searchParams.get("tab") || "";
  const categoryParam = searchParams.get("category") || "";
  const [query, setQuery] = useState(() => searchParams.get("q") || "");
  const [searchQuery, setSearchQuery] = useState(() => searchParams.get("q") || "");

  const selectedTab = useMemo(() => {
    const found = rankingTabs.findIndex((item) => item.key === tabParam);
    return found >= 0 ? found : 0;
  }, [tabParam]);

  const selectedCategory = useMemo(() => {
    return rankingCategories.some((item) => item.key === categoryParam) ? categoryParam : "";
  }, [categoryParam]);

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
    return items.filter((item) =>
      [item.name, item.merchant, item.description, ...item.tags].join(" ").toLowerCase().includes(normalized)
    );
  }, [items, searchQuery]);

  const featuredItem = useMemo(() => {
    if (searchQuery.trim()) return undefined;
    return weeklyTop || filteredItems.find((item) => item.rank === 1) || filteredItems[0];
  }, [filteredItems, searchQuery, weeklyTop]);

  const listItems = featuredItem
    ? filteredItems.filter((item) => item.id !== featuredItem.id)
    : filteredItems;

  function rankingUrl(tabKey = rankingTabs[selectedTab].key, category = selectedCategory, text = searchQuery) {
    const params = new URLSearchParams();
    if (tabKey) params.set("tab", tabKey);
    if (category) params.set("category", category);
    if (text.trim()) params.set("q", text.trim());
    const qs = params.toString();
    return `${pathname}${qs ? `?${qs}` : ""}`;
  }

  function submitSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSearchQuery(query);
    router.replace(rankingUrl(undefined, undefined, query), { scroll: false });
  }

  function selectTab(index: number) {
    const nextCategory = index > 0 && !selectedCategory ? "CUP" : selectedCategory;
    router.replace(rankingUrl(rankingTabs[index].key, nextCategory), { scroll: false });
  }

  function selectCategory(key: string) {
    const nextCategory = selectedTab === 0 && selectedCategory === key ? "" : key;
    router.replace(rankingUrl(undefined, nextCategory), { scroll: false });
  }

  function openSubmission() {
    if (user) {
      router.push("/ranking/submit");
      return;
    }
    router.push(`/login?next=${encodeURIComponent("/ranking/submit")}`);
  }

  const returnPath = rankingUrl();

  return (
    <>
      {/* 桌面端专用导航栏 */}
      <SiteHeader className="ranking-site-header" />

      {/* 移动端原型顶部 Header */}
      <header className="rank-head mobile-only">
        <button
          type="button"
          className="icon-btn"
          aria-label="返回首页"
          onClick={() => router.push("/")}
        >
          <Icon name="chevron-left" size={22} />
        </button>

        <form className="searchbox" onSubmit={submitSearch} role="search">
          <Icon name="search" size={16} />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="搜索：魅魔、大雕王、慢玩..."
            aria-label="搜索榜单商品"
          />
        </form>

        <button
          type="button"
          className="icon-btn"
          aria-label="提交榜单商品"
          onClick={openSubmission}
        >
          <Icon name="plus" size={18} />
        </button>
        <button
          type="button"
          className="icon-btn"
          aria-label="切换排序模式"
          onClick={() => showToast("已按热度智能排序")}
        >
          <Icon name="refresh" size={17} />
        </button>
      </header>

      {/* 移动端原型分类导航条 */}
      <nav className="rank-tabs mobile-only" aria-label="榜单类型">
        {rankingTabs.map((tab, index) => (
          <button
            key={tab.key || "all"}
            type="button"
            className={selectedTab === index ? "active" : ""}
            onClick={() => selectTab(index)}
          >
            {tab.label}
          </button>
        ))}
      </nav>

      {/* 移动端原型商品分类条 */}
      <div className="category-strip mobile-only" aria-label="商品分类">
        {rankingCategories.map((category) => (
          <button
            key={category.key}
            type="button"
            className={`cat-pill${selectedCategory === category.key ? " active" : ""}`}
            onClick={() => selectCategory(category.key)}
          >
            <Icon name={category.icon} size={14} />
            <span>{category.label}</span>
          </button>
        ))}
      </div>

      <main className="page-frame ranking-page-frame">
        <section className="feature-page ranking-page">
          {/* 桌面端 Hero Banner */}
          <div className="feature-hero desktop-only">
            <div>
              <span className="feature-kicker">
                <Icon name="trophy" size={16} /> 北邮酱榜单
              </span>
              <h1>本周好物榜</h1>
              <p>看看大家最近在关注什么，找到适合自己的那一款。</p>
            </div>
            <Link href="/?sort=hot" className="outline-button feature-back">
              回到社区
            </Link>
          </div>

          {/* 桌面端分类与筛选 */}
          <div className="ranking-desktop-navigation desktop-only">
            <nav className="ranking-tabs-desktop" aria-label="桌面端榜单类型">
              {rankingTabs.map((tab, index) => (
                <button
                  key={tab.key || "all"}
                  type="button"
                  className={selectedTab === index ? "active" : ""}
                  onClick={() => selectTab(index)}
                >
                  {tab.label}
                </button>
              ))}
            </nav>
            <div className="ranking-categories-desktop" aria-label="桌面端商品分类">
              {rankingCategories.map((category) => (
                <button
                  key={category.key}
                  type="button"
                  className={`ranking-category-pill${selectedCategory === category.key ? " active" : ""}`}
                  onClick={() => selectCategory(category.key)}
                >
                  <Icon name={category.icon} size={16} />
                  <span>{category.label}</span>
                </button>
              ))}
            </div>
          </div>

          {error && <div className="data-note" role="status">{error}</div>}

          {/* 桌面端商品栅格展示 */}
          <div className="desktop-only">
            {loading ? (
              <div className="ranking-grid" aria-label="榜单加载中">
                <div className="ranking-skeleton" />
                <div className="ranking-skeleton" />
                <div className="ranking-skeleton" />
              </div>
            ) : items.length ? (
              <>
                {featuredItem && (
                  <div className="ranking-desktop-featured">
                    <RankingCard item={featuredItem} returnPath={returnPath} />
                  </div>
                )}
                <div className="ranking-grid">
                  {listItems.map((item) => (
                    <RankingCard key={item.id} item={item} returnPath={returnPath} />
                  ))}
                </div>
              </>
            ) : (
              <div className="empty-state feature-empty">
                <span className="empty-icon"><Icon name="trophy" size={24} /></span>
                <h2>榜单正在准备中</h2>
                <p>{searchQuery ? "未找到匹配的榜单商品。" : "先去社区看看大家最近的真实分享吧。"}</p>
                <Link href="/" className="primary-link">浏览帖子</Link>
              </div>
            )}
          </div>

          {/* 移动端商品原型列表展示 */}
          <div className="rank-list mobile-only">
            {loading ? (
              <div className="loading-stack" style={{ padding: 12 }}>
                <div className="skeleton-card" />
                <div className="skeleton-card short" />
              </div>
            ) : items.length ? (
              <>
                {featuredItem && (
                  <Link
                    href={`/ranking/${encodeURIComponent(featuredItem.id)}?from=${encodeURIComponent(returnPath)}`}
                    className="featured-card-link"
                  >
                    <article className="featured" data-rank-id={featuredItem.id}>
                      <div className="featured-banner">
                        {featuredItem.heroUrl || featuredItem.coverUrl ? (
                          <MediaImage
                            sources={[featuredItem.heroUrl, featuredItem.coverUrl]}
                            alt={featuredItem.name}
                            loading="eager"
                          />
                        ) : (
                          <div className="banner-ph">
                            <span className="ph-text">本周霸权 · TOP 1</span>
                          </div>
                        )}
                      </div>
                      <div className="feat-body">
                        <div className="feat-top">
                          <h3 className="feat-title">{featuredItem.name}</h3>
                          <span className="feat-score">
                            {scoreText(featuredItem.score)}
                            <small>分</small>
                          </span>
                        </div>
                        {featuredItem.tags.length > 0 && (
                          <div className="tags">
                            {featuredItem.tags.slice(0, 3).map((tag) => (
                              <span key={tag} className="tag">
                                #{tag}
                              </span>
                            ))}
                          </div>
                        )}
                      </div>
                    </article>
                  </Link>
                )}

                {listItems.map((item, idx) => {
                  const displayRank = item.rank || idx + 2;
                  const isTop3 = displayRank <= 3;
                  return (
                    <Link
                      key={item.id}
                      href={`/ranking/${encodeURIComponent(item.id)}?from=${encodeURIComponent(returnPath)}`}
                      className="rank-row-link"
                    >
                      <article className="rank-row" data-rank-id={item.id}>
                        <div className={`num${isTop3 ? " top3" : ""}`}>{displayRank}</div>
                        <div className="rank-thumb">
                          <MediaImage
                            sources={[item.coverUrl, item.heroUrl]}
                            alt={item.name}
                            loading="lazy"
                          />
                        </div>
                        <div className="rank-main">
                          <h4 className="rank-title">{item.name}</h4>
                          {item.tags.length > 0 && (
                            <div className="tags">
                              {item.tags.slice(0, 2).map((tag) => (
                                <span key={tag} className="tag">
                                  #{tag}
                                </span>
                              ))}
                            </div>
                          )}
                          <div className="rank-meta">
                            {compactCount(item.ratingCount || 19)}人评分
                          </div>
                        </div>
                        <div className="rank-side">
                          <div className="rank-want">{compactCount(item.wantCount || 300)}人想冲</div>
                          <div className="score">
                            {scoreText(item.score)}
                            <small>分</small>
                          </div>
                        </div>
                      </article>
                    </Link>
                  );
                })}
              </>
            ) : (
              <div className="empty-state">
                <span className="empty-icon"><Icon name="trophy" size={24} /></span>
                <h2>榜单正在准备中</h2>
                <p>{searchQuery ? "未找到匹配的榜单商品。" : "先去社区看看大家最近的真实分享吧。"}</p>
                <Link href="/" className="primary-link">浏览帖子</Link>
              </div>
            )}
          </div>
        </section>
      </main>

      {/* 底部导航栏上方的下载 App 窗口（移动端严格保留） */}
      <AppDownloadBanner />

      {/* 移动端底部导航栏 */}
      <BottomNav activeNav="home" />
    </>
  );
}

function RankingCard({ item, returnPath }: { item: RankingToy; returnPath: string }) {
  return (
    <Link
      href={`/ranking/${encodeURIComponent(item.id)}?from=${encodeURIComponent(returnPath)}`}
      className="ranking-card-link"
    >
      <article className="ranking-card">
        <div className={`ranking-card-rank rank-${item.rank}`}>{item.rank}</div>
        <div className="ranking-cover">
          <MediaImage sources={[item.coverUrl, item.heroUrl]} alt={item.name} />
        </div>
        <div className="ranking-card-copy">
          <div className="ranking-card-title">
            <h2>{item.name}</h2>
            <strong>{scoreText(item.score)}</strong>
          </div>
          {item.merchant && <p className="ranking-merchant">{item.merchant}</p>}
          <p className="ranking-description">{item.description || "暂无产品介绍"}</p>
          <div className="ranking-card-meta">
            <span>{compactCount(item.wantCount)} 人想要</span>
            <span>{compactCount(item.ratingCount)} 条评价</span>
          </div>
          {item.tags.length > 0 && (
            <div className="ranking-tags">
              {item.tags.slice(0, 3).map((tag) => (
                <span key={tag}>{tag}</span>
              ))}
            </div>
          )}
        </div>
        <div className="ranking-mobile-score">
          {scoreText(item.score)}
          <small>分</small>
        </div>
      </article>
    </Link>
  );
}
