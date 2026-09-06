"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "../../components/site-header";
import { AppDownloadBanner } from "../../components/app-download-banner";
import { BottomNav } from "../../components/bottom-nav";
import { Icon } from "../../components/icons";
import { useSession } from "../../components/session-provider";
import { useInfiniteScroll } from "../../lib/use-infinite-scroll";
import { getMyPoints, getMyProfileList, getUserProfile } from "../../lib/api/forum";
import { compactCount, formatError, relativeTime } from "../../lib/format";
import type { ProfilePost, ProfileSummary } from "../../types/forum";

type TabKind = "posts" | "comments" | "bookmarks" | "likes" | "history";

const TABS: Array<{ kind: TabKind; label: string; icon: "message" | "heart" | "bookmark" | "history" | "sparkle" }> = [
  { kind: "posts", label: "我的发帖", icon: "message" },
  { kind: "comments", label: "我的回复", icon: "message" },
  { kind: "bookmarks", label: "我的收藏", icon: "bookmark" },
  { kind: "likes", label: "我的点赞", icon: "heart" },
  { kind: "history", label: "浏览历史", icon: "history" },
];

export default function MyWorkbenchPage() {
  const router = useRouter();
  const { user, ready, isGuest, isRegistered } = useSession();
  const [profile, setProfile] = useState<ProfileSummary | null>(null);
  const [points, setPoints] = useState<number | null>(null);
  const [pointsError, setPointsError] = useState(false);
  const [summaryRetry, setSummaryRetry] = useState(0);
  const [activeTab, setActiveTab] = useState<TabKind>("posts");
  const [items, setItems] = useState<ProfilePost[]>([]);
  const [nextCursor, setNextCursor] = useState<string>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [loadMoreError, setLoadMoreError] = useState(false);
  const [error, setError] = useState("");
  const listGeneration = useRef(0);

  useEffect(() => {
    if (!ready) return;
    if (!user) {
      router.replace(`/login?next=${encodeURIComponent("/me")}`);
      return;
    }

    let active = true;
    setProfile(null);
    setPoints(null);
    setPointsError(false);
    void Promise.allSettled([getUserProfile(user.id), getMyPoints()]).then(([profileResult, pointsResult]) => {
      if (!active) return;
      setProfile(profileResult.status === "fulfilled" ? profileResult.value : null);
      if (pointsResult.status === "fulfilled") {
        setPoints(pointsResult.value.points);
      } else {
        setPoints(null);
        setPointsError(true);
      }
    });

    return () => {
      active = false;
    };
  }, [ready, router, summaryRetry, user]);

  useEffect(() => {
    if (!ready || !user) return;
    let active = true;
    const generation = ++listGeneration.current;
    setLoading(true);
    setLoadingMore(false);
    setLoadMoreError(false);
    setError("");
    void getMyProfileList(activeTab)
      .then((res) => {
        if (!active || generation !== listGeneration.current) return;
        setItems(res.items);
        setNextCursor(res.nextCursor);
        setHasMore(res.hasMore);
      })
      .catch((err: unknown) => {
        if (active && generation === listGeneration.current) setError(formatError(err, "列表加载失败，请稍后重试"));
      })
      .finally(() => {
        if (active && generation === listGeneration.current) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [activeTab, ready, user]);

  async function handleTabChange(tab: TabKind) {
    if (tab === activeTab) return;
    listGeneration.current += 1;
    setActiveTab(tab);
  }

  const handleLoadMore = useCallback(async () => {
    if (!nextCursor || loadingMore) return;
    const generation = listGeneration.current;
    setLoadingMore(true);
    setLoadMoreError(false);
    try {
      const res = await getMyProfileList(activeTab, nextCursor);
      if (generation !== listGeneration.current) return;
      setItems((curr) => [...curr, ...res.items]);
      setNextCursor(res.nextCursor);
      setHasMore(res.hasMore);
    } catch {
      if (generation === listGeneration.current) setLoadMoreError(true);
    } finally {
      if (generation === listGeneration.current) setLoadingMore(false);
    }
  }, [activeTab, loadingMore, nextCursor]);

  const sentinelRef = useInfiniteScroll({
    hasMore,
    loading: loading || loadingMore,
    onLoadMore: handleLoadMore,
    disabled: loadMoreError,
  });

  if (!ready || !user) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame">
          <div className="detail-skeleton">
            <div />
            <div />
          </div>
        </main>
      </>
    );
  }

  return (
    <>
      <SiteHeader />

      <main className="page-frame workbench-page" style={{ maxWidth: 960, margin: "0 auto", padding: "24px 16px 80px" }}>
        {/* 顶部工作台标题栏 */}
        <section className="workbench-header-card">
          <div className="workbench-header-main">
            <div>
              <h1 className="workbench-title">我的工作台</h1>
              <p className="workbench-subtitle">管理你的内容、收藏与社区成长</p>
            </div>
            {isRegistered && (
              <div className="workbench-header-aside">
                <span className="workbench-user-badge">
                  @{user.username} · Lv.{profile?.level || user.level || 1}
                </span>
                <Link href={`/user/${encodeURIComponent(user.id)}`} className="workbench-public-link">
                  查看公开主页 <Icon name="chevron-right" size={14} />
                </Link>
              </div>
            )}
          </div>

          {/* 游客升级提示栏 */}
          {isGuest && (
            <div className="workbench-guest-banner">
              <div className="workbench-guest-info">
                <span className="workbench-guest-tag">
                  <Icon name="eye" size={14} />
                  游客模式
                </span>
                <p className="workbench-guest-desc">
                  注册正式账号后可永久保留当前游客身份产生的数据与经验，并解锁发帖与收藏特权。
                </p>
              </div>
              <div className="workbench-guest-actions">
                <button
                  type="button"
                  className="workbench-btn-secondary"
                  onClick={() => router.push(`/login?mode=login&next=${encodeURIComponent("/me")}`)}
                >
                  登录已有账号
                </button>
                <button
                  type="button"
                  className="workbench-btn-primary"
                  onClick={() => router.push(`/login?mode=register&next=${encodeURIComponent("/me")}`)}
                >
                  注册正式账号
                </button>
              </div>
            </div>
          )}
        </section>

        {/* 4 列可点击数据卡片 */}
        <section className="workbench-stats-grid">
          <button
            type="button"
            className={`workbench-stat-card ${activeTab === "posts" ? "active" : ""}`}
            onClick={() => handleTabChange("posts")}
          >
            <strong className="workbench-stat-val">{profile ? compactCount(profile.postCount) : "—"}</strong>
            <span className="workbench-stat-lbl">我的发帖</span>
          </button>
          <button
            type="button"
            className={`workbench-stat-card ${activeTab === "comments" ? "active" : ""}`}
            onClick={() => handleTabChange("comments")}
          >
            <strong className="workbench-stat-val">{profile ? compactCount(profile.commentCount) : "—"}</strong>
            <span className="workbench-stat-lbl">我的回复</span>
          </button>
          <button
            type="button"
            className={`workbench-stat-card ${activeTab === "bookmarks" ? "active" : ""}`}
            onClick={() => handleTabChange("bookmarks")}
          >
            <strong className="workbench-stat-val">{profile ? compactCount(profile.bookmarkCount) : "—"}</strong>
            <span className="workbench-stat-lbl">我的收藏</span>
          </button>
          <button
            type="button"
            className="workbench-stat-card workbench-stat-points"
            onClick={() => {
              if (pointsError) setSummaryRetry((value) => value + 1);
              else router.push("/points");
            }}
            title="进入积分中心"
          >
            <div className="workbench-points-val">
              <strong style={{ color: "#d97706" }}>{points === null ? (pointsError ? "积分暂时无法加载 · 重试" : "加载中…") : compactCount(points)}</strong>
              <Icon name="chevron-right" size={16} />
            </div>
            <span className="workbench-stat-lbl">我的积分 →</span>
          </button>
        </section>

        {/* 内容管理区与 Tab 导航 */}
        <section className="workbench-content-section">
          <div className="workbench-tabs-bar">
            <h2 className="workbench-section-heading">内容管理</h2>
            <div className="workbench-tabs-scroll">
              {TABS.map((tab) => (
                <button
                  key={tab.kind}
                  type="button"
                  onClick={() => handleTabChange(tab.kind)}
                  className={`workbench-tab-pill ${activeTab === tab.kind ? "active" : ""}`}
                >
                  <Icon name={tab.icon} size={15} />
                  <span>{tab.label}</span>
                </button>
              ))}
            </div>
          </div>

          {error && <div className="data-note" role="status" style={{ marginBottom: 16 }}>{error}</div>}

          {/* 列表内容 */}
          {loading ? (
            <div className="detail-skeleton">
              <div />
              <div />
            </div>
          ) : items.length > 0 ? (
            <div className="profile-post-list">
              {items.map((item) => {
                const rowKey = item.commentId ? `${item.id}-${item.commentId}` : item.id;
                const href = item.commentId
                  ? `/post/${encodeURIComponent(item.id)}#comment-${encodeURIComponent(item.commentId)}`
                  : `/post/${encodeURIComponent(item.id)}`;
                const timeDisplay = relativeTime(item.activityAt || item.createdAt);
                return (
                  <Link key={rowKey} href={href} className="profile-post-row">
                    <div>
                      <span className="profile-post-community">{item.communityName}</span>
                      <h3>{item.title}</h3>
                      <p>{item.contentPreview || "（此内容未提供文字摘要）"}</p>
                    </div>
                    <div className="profile-post-meta">
                      <span>{timeDisplay}</span>
                      <span>{compactCount(item.commentCount)} 回复</span>
                      <span>{compactCount(item.likeCount)} 赞</span>
                    </div>
                  </Link>
                );
              })}

              {hasMore && (
                <div ref={sentinelRef} className="feed-load-sentinel">
                  {loadingMore && (
                    <div className="feed-load-indicator">
                      <span className="feed-spinner" />
                      <span>正在加载更多…</span>
                    </div>
                  )}
                  {loadMoreError && (
                    <button
                      type="button"
                      className="feed-load-retry"
                      onClick={() => {
                        setLoadMoreError(false);
                        void handleLoadMore();
                      }}
                    >
                      加载失败 · 点击重试
                    </button>
                  )}
                </div>
              )}

              {!hasMore && (
                <div className="feed-end" style={{ margin: "20px 0 10px" }}>已经到底啦</div>
              )}
            </div>
          ) : (
            <div className="workbench-empty-compact">
              <div className="workbench-empty-icon">
                <Icon name="sparkle" size={20} />
              </div>
              <div className="workbench-empty-info">
                <h3>暂无{TABS.find((t) => t.kind === activeTab)?.label}内容</h3>
                <p>去社区里发现好玩的内容并参与讨论吧</p>
              </div>
              <Link href="/" className="workbench-empty-action">
                去逛逛
              </Link>
            </div>
          )}
        </section>
      </main>

      <footer className="profile-version-footer" style={{ textAlign: "center", padding: "16px 0 24px" }}>
        <a
          href="/api/version"
          target="_blank"
          rel="noreferrer"
          style={{ fontSize: 12, color: "#94a3b8", textDecoration: "none", fontFamily: "monospace" }}
        >
          Web Build: {process.env.NEXT_PUBLIC_GIT_SHA ? process.env.NEXT_PUBLIC_GIT_SHA.slice(0, 7) : "dev"}
        </a>
      </footer>

      <AppDownloadBanner />
      <BottomNav activeNav="profile" />
    </>
  );
}
