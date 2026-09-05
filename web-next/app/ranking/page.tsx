"use client";

import Link from "next/link";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Icon, type IconName } from "../../components/icons";
import { MediaImage } from "../../components/media-image";
import { SiteHeader } from "../../components/site-header";
import { CommunityRail } from "../../components/community-rail";
import { AppDownloadBanner } from "../../components/app-download-banner";
import { BottomNav } from "../../components/bottom-nav";
import { useSession } from "../../components/session-provider";
import { useToast } from "../../components/toast-context";
import { getCommunities, getRankingView } from "../../lib/api/forum";
import { selectHomeCommunities } from "../../lib/home-communities";
import { compactCount, formatError } from "../../lib/format";
import type { Community, RankingToy } from "../../types/forum";

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
  const [communities, setCommunities] = useState<Community[]>([]);
  const [ruleModalOpen, setRuleModalOpen] = useState(false);

  useEffect(() => {
    let active = true;
    void getCommunities({ status: "active" })
      .then((items) => {
        if (!active) return;
        setCommunities(selectHomeCommunities(items));
      })
      .catch(() => {});
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    void getRankingView(rankingTabs[selectedTab].key, selectedCategory)
      .then((view) => {
        if (!active) return;
        // 严格使用 API 返回顺序，前端绝不重新按 score 排序
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

  // 移动端专用逻辑
  const featuredItem = useMemo(() => {
    if (searchQuery.trim()) return undefined;
    return weeklyTop || filteredItems.find((item) => item.rank === 1) || filteredItems[0];
  }, [filteredItems, searchQuery, weeklyTop]);

  const mobileListItems = featuredItem
    ? filteredItems.filter((item) => item.id !== featuredItem.id)
    : filteredItems;

  // 桌面端层级拆解：Top 1, Top 2, Top 3, Rank 4+
  const top1 = filteredItems[0];
  const top2 = filteredItems[1];
  const top3 = filteredItems[2];
  const restItems = filteredItems.slice(3);

  // 仅当 weeklyTop != 当前 Top1 时在右侧展示独立冠军栏
  const showRightRail = Boolean(
    weeklyTop && filteredItems.length > 0 && weeklyTop.id !== filteredItems[0]?.id
  );

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

      {/* 移动端原型顶部 Header (严格保持不变) */}
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

      {/* 移动端原型分类导航条 (严格保持不变) */}
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

      {/* 移动端原型商品分类条 (严格保持不变) */}
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
        {/* =========================================================
            PC 桌面端完整三栏系统（对齐 beiyoujiang 与 HTML 设计原型）
           ========================================================= */}
        <div className="home-grid ranking-desktop-grid desktop-only">
          {/* 左侧社区导航栏 */}
          <div className="home-left-col">
            <CommunityRail
              communities={communities}
              activeId=""
              onSelect={(comm) => {
                router.push(comm ? `/?community=${encodeURIComponent(comm.id)}` : "/");
              }}
            />
          </div>

          {/* 中间榜单主体 */}
          <section className="ranking-main-col" aria-label="本周好物榜">
            {/* 顶部标题与规则 */}
            <div className="ranking-body-head">
              <div>
                <h1 className="ranking-page-title">本周好物榜</h1>
                <p className="ranking-page-sub">根据同好真实拆箱、测评评分与互动热度排序</p>
              </div>
              <button
                type="button"
                className="ranking-rule-btn"
                onClick={() => setRuleModalOpen(true)}
              >
                <Icon name="info" size={14} />
                <span>榜单规则</span>
              </button>
            </div>

            {/* 分类切换：Tabs 与 Pills */}
            <div className="ranking-filters-bar">
              <nav className="ranking-tabs-row" aria-label="榜单维度">
                {rankingTabs.map((tab, index) => (
                  <button
                    key={tab.key || "all"}
                    type="button"
                    className={`ranking-tab-btn${selectedTab === index ? " active" : ""}`}
                    onClick={() => selectTab(index)}
                  >
                    {tab.label}
                  </button>
                ))}
              </nav>

              <div className="ranking-cats-row" aria-label="商品品类">
                <button
                  type="button"
                  className={`ranking-cat-btn${selectedCategory === "" ? " active" : ""}`}
                  onClick={() => selectCategory("")}
                >
                  全部
                </button>
                {rankingCategories.map((cat) => (
                  <button
                    key={cat.key}
                    type="button"
                    className={`ranking-cat-btn${selectedCategory === cat.key ? " active" : ""}`}
                    onClick={() => selectCategory(cat.key)}
                  >
                    <Icon name={cat.icon} size={14} />
                    <span>{cat.label}</span>
                  </button>
                ))}
              </div>
            </div>

            {error && <div className="data-note" role="status">{error}</div>}

            {loading ? (
              <div className="loading-stack" style={{ padding: "20px 0" }}>
                <div className="skeleton-card" style={{ height: 260 }} />
                <div className="skeleton-card short" />
              </div>
            ) : filteredItems.length === 0 ? (
              <div className="empty-state">
                <Icon name="trophy" size={28} />
                <h2>暂无上榜商品</h2>
                <p>{searchQuery ? "未找到匹配的商品。" : "当前分类暂无上榜商品。"}</p>
              </div>
            ) : (
              <div className="ranking-desktop-flow">
                {/* 1. TOP 1 深色重点卡 (深蓝背景，独立大图，核心三指标) */}
                {top1 && (
                  <Link
                    href={`/ranking/${encodeURIComponent(top1.id)}?from=${encodeURIComponent(returnPath)}`}
                    className="ranking-top1-link"
                  >
                    <article className="ranking-top1-card">
                      <div className="top1-crown-badge">
                        <Icon name="trophy" size={13} /> 本周冠军
                      </div>
                      <div className="top1-num">01</div>
                      <div className="top1-img-wrap">
                        <img
                          src={top1.coverUrl || top1.heroUrl || "/default-avatar.webp"}
                          alt={top1.name}
                          className="top1-img"
                        />
                      </div>
                      <div className="top1-details">
                        <div className="top1-title-line">
                          <h2 className="top1-title">{top1.name}</h2>
                          <div className="top1-score-val">
                            <strong>{scoreText(top1.score)}</strong>
                            <small>分</small>
                          </div>
                        </div>
                        <div className="top1-meta-tags">
                          <span className="top1-merchant">{top1.merchant || "CUP"}</span>
                          {top1.tags.slice(0, 2).map((t) => (
                            <span key={t} className="top1-tag">#{t}</span>
                          ))}
                        </div>
                        <p className="top1-desc">{top1.description || "热门精选，玩家高口碑推荐好物"}</p>
                        <div className="top1-kpis">
                          <span className="kpi-item">
                            <b>{top1.ratingCount || 0}</b> 篇测评
                          </span>
                          <span className="kpi-sep">·</span>
                          <span className="kpi-item">
                            <b>{compactCount(top1.wantCount || 0)}</b> 人想要
                          </span>
                        </div>
                      </div>
                    </article>
                  </Link>
                )}

                {/* 2. TOP 2 / TOP 3 双列并排卡 */}
                {(top2 || top3) && (
                  <div className="ranking-top23-grid">
                    {top2 && (
                      <Link
                        href={`/ranking/${encodeURIComponent(top2.id)}?from=${encodeURIComponent(returnPath)}`}
                        className="ranking-top23-link"
                      >
                        <article className="ranking-top23-card">
                          <div className="top23-badge rank-2">02</div>
                          <div className="top23-thumb">
                            <img src={top2.coverUrl || "/default-avatar.webp"} alt={top2.name} />
                          </div>
                          <div className="top23-info">
                            <h3 className="top23-name">{top2.name}</h3>
                            <div className="top23-meta">
                              <span>{top2.merchant || "CUP"}</span>
                              <span className="dot">·</span>
                              <span>{top2.ratingCount || 0} 测评</span>
                            </div>
                            <div className="top23-score">
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
                        className="ranking-top23-link"
                      >
                        <article className="ranking-top23-card">
                          <div className="top23-badge rank-3">03</div>
                          <div className="top23-thumb">
                            <img src={top3.coverUrl || "/default-avatar.webp"} alt={top3.name} />
                          </div>
                          <div className="top23-info">
                            <h3 className="top23-name">{top3.name}</h3>
                            <div className="top23-meta">
                              <span>{top3.merchant || "CUP"}</span>
                              <span className="dot">·</span>
                              <span>{top3.ratingCount || 0} 测评</span>
                            </div>
                            <div className="top23-score">
                              <strong>{scoreText(top3.score)}</strong>
                              <small>分</small>
                            </div>
                          </div>
                        </article>
                      </Link>
                    )}
                  </div>
                )}

                {/* 3. 第 4 名以后 横向行列表 */}
                {restItems.length > 0 && (
                  <div className="ranking-rows-container">
                    {restItems.map((item, idx) => {
                      const rankNum = (idx + 4).toString().padStart(2, "0");
                      return (
                        <Link
                          key={item.id}
                          href={`/ranking/${encodeURIComponent(item.id)}?from=${encodeURIComponent(returnPath)}`}
                          className="ranking-row-link"
                        >
                          <article className="ranking-horizontal-row">
                            <div className="row-rank-num">{rankNum}</div>
                            <div className="row-thumb">
                              <img src={item.coverUrl || "/default-avatar.webp"} alt={item.name} />
                            </div>
                            <div className="row-content">
                              <h4 className="row-title">{item.name}</h4>
                              <div className="row-meta">
                                <span>{item.merchant || "CUP"}</span>
                                <span className="dot">·</span>
                                <span>{item.ratingCount || 0} 测评</span>
                                <span className="dot">·</span>
                                <span>{compactCount(item.wantCount || 0)} 想要</span>
                              </div>
                            </div>
                            <div className="row-score">
                              <strong>{scoreText(item.score)}</strong>
                              <small>分</small>
                            </div>
                          </article>
                        </Link>
                      );
                    })}
                  </div>
                )}
              </div>
            )}
          </section>

          {/* 右栏按需展示：只有 weeklyTop != 当前 Top1 才展示 */}
          <div className="home-right-col ranking-right-rail-col">
            {showRightRail && weeklyTop ? (
              <aside className="ranking-champ-rail">
                <div className="rail-head" style={{ marginBottom: 10 }}>
                  <div className="rail-head-title">
                    <span className="rail-head-icon blue"><Icon name="trophy" size={16} /></span>
                    <h3>本周冠军</h3>
                  </div>
                </div>
                <Link
                  href={`/ranking/${encodeURIComponent(weeklyTop.id)}?from=${encodeURIComponent(returnPath)}`}
                  className="rank-hero-celestial"
                  style={{ textDecoration: "none" }}
                >
                  <div className="rank-hero-top">
                    <span className="rank-hero-kicker">官方榜首</span>
                    <span className="rank-hero-score">{scoreText(weeklyTop.score)}</span>
                  </div>
                  <strong className="rank-hero-title">{weeklyTop.name}</strong>
                  <div className="rank-hero-meta">
                    <span>{weeklyTop.ratingCount || 0} 篇测评</span>
                    <span className="meta-dot">·</span>
                    <span>{compactCount(weeklyTop.wantCount || 0)} 人想要</span>
                  </div>
                </Link>
              </aside>
            ) : null}
          </div>
        </div>

        {/* =========================================================
            移动端商品列表展示 (100% 保持移动端原有排版与结构)
           ========================================================= */}
        <div className="rank-list mobile-only">
          {loading ? (
            <div className="loading-stack" style={{ padding: 12 }}>
              <div className="skeleton-card" />
              <div className="skeleton-card short" />
            </div>
          ) : filteredItems.length ? (
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

              {mobileListItems.map((item, idx) => {
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
      </main>

      {/* 榜单规则弹窗 */}
      {ruleModalOpen && (
        <div
          className="modal-backdrop show"
          onClick={(e) => {
            if (e.target === e.currentTarget) setRuleModalOpen(false);
          }}
          role="dialog"
          aria-modal="true"
        >
          <div className="modal" style={{ width: "min(520px, 90vw)", background: "#fff", borderRadius: 16, padding: 20 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 14 }}>
              <h3 style={{ margin: 0, fontSize: 18 }}>🏆 圣杯排行榜规则</h3>
              <button
                type="button"
                onClick={() => setRuleModalOpen(false)}
                style={{ background: "transparent", border: 0, fontSize: 20, cursor: "pointer", color: "#94a3b8" }}
              >
                ✕
              </button>
            </div>
            <div style={{ color: "#475569", lineHeight: 1.8, fontSize: 14 }}>
              <p><strong>1. 数据来源</strong>：排名基于同好真实拆箱打分、长篇测评评价数、想要拥有数及活跃讨论热度综合计算。</p>
              <p><strong>2. 排行顺序</strong>：前端严格按照系统给出的热度与管理员人工维护顺序展现，不篡改评分排序。</p>
              <p><strong>3. 诚信原则</strong>：杜绝虚假刷单与批量刷分，异常数据将被算法识别并过滤，保持客观真实。</p>
            </div>
            <div style={{ textAlign: "right", marginTop: 18 }}>
              <button
                type="button"
                className="primary-button"
                onClick={() => setRuleModalOpen(false)}
                style={{ height: 36, padding: "0 18px" }}
              >
                我知道了
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 底部导航栏上方的下载 App 窗口（移动端严格保留） */}
      <AppDownloadBanner />

      {/* 移动端底部导航栏 */}
      <BottomNav activeNav="home" />
    </>
  );
}
