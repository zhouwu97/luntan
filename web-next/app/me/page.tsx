"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "../../components/site-header";
import { AppDownloadBanner } from "../../components/app-download-banner";
import { BottomNav } from "../../components/bottom-nav";
import { Icon } from "../../components/icons";
import { useSession } from "../../components/session-provider";
import { UserAvatar } from "../../components/user-avatar";
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
  const { user, ready, isGuest, isRegistered, unreadCount } = useSession();
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

      {/* 移动端按 App 的“我的”信息架构展示，桌面端继续保留工作台布局。 */}
      <section className="mobile-profile-page">
        <header className="mobile-profile-header">
          <h1>我的</h1>
          <div className="mobile-profile-header-actions">
            <button type="button" aria-label="通知" onClick={() => router.push("/notifications")}>
              <Icon name="bell" size={22} />
              {unreadCount > 0 && <span className="mobile-profile-badge">{unreadCount > 99 ? "99+" : unreadCount}</span>}
            </button>
            <button type="button" aria-label="设置" onClick={() => router.push("/settings")}>
              <Icon name="settings" size={23} />
            </button>
          </div>
        </header>

        <section className="mobile-profile-card">
          <button type="button" className="mobile-profile-card-head" onClick={() => router.push(`/user/${encodeURIComponent(user.id)}`)}>
            <UserAvatar userId={user.id} name={user.nickname} url={user.avatarUrl} size="profile" className="mobile-profile-avatar" />
            <span className="mobile-profile-copy">
              <strong>{user.nickname || "用户"}</strong>
              <small>{user.email || `@${user.username}`} · Lv.{profile?.level || user.level || 1}</small>
              <em>{profile?.bio || "还没有个性签名，点进主页完善资料"}</em>
            </span>
            <span className="mobile-profile-public">个人主页 <Icon name="chevron-right" size={16} /></span>
          </button>
          <div className="mobile-profile-stats">
            {[
              [profile?.postCount ?? 0, "我的发布", "posts" as TabKind],
              [profile?.commentCount ?? 0, "我的评论", "comments" as TabKind],
              [profile?.followerCount ?? 0, "粉丝", null],
              [profile?.followingCount ?? 0, "关注", null],
            ].map(([count, label, tab]) => (
              <button key={label as string} type="button" onClick={() => tab && void handleTabChange(tab as TabKind)}>
                <strong>{count as number}</strong>
                <span>{label as string}</span>
              </button>
            ))}
          </div>
        </section>

        <button type="button" className="mobile-points-card" onClick={() => router.push("/points")}>
          <span className="mobile-points-mark"><Icon name="star" size={18} /></span>
          <span className="mobile-points-copy"><small>社区积分</small><strong>{points === null ? (pointsError ? "暂不可用" : "加载中…") : `${compactCount(points)} 积分`}</strong><em>当前可用积分 {points ?? 0}</em></span>
          <span className="mobile-points-actions"><span>明细</span><span onClick={(event) => { event.stopPropagation(); router.push("/points?tab=store"); }}>兑换</span><em>查看积分明细 <Icon name="chevron-right" size={14} /></em></span>
        </button>

        <section className="mobile-profile-section">
          <h2>常用功能</h2>
          <div className="mobile-tools-grid">
            <button type="button" onClick={() => void handleTabChange("bookmarks")}><span className="tool-icon tool-icon-orange"><Icon name="star" size={21} /></span><span>我的收藏</span></button>
            <button type="button" onClick={() => void handleTabChange("likes")}><span className="tool-icon tool-icon-pink"><Icon name="heart" size={21} /></span><span>我的点赞</span></button>
            <button type="button" onClick={() => void handleTabChange("history")}><span className="tool-icon tool-icon-blue"><Icon name="history" size={21} /></span><span>浏览历史</span></button>
            <button type="button" onClick={() => router.push("/appeals")}><span className="tool-icon tool-icon-mint"><Icon name="bell" size={21} /></span><span>我的申诉</span></button>
          </div>
        </section>

        <section className="mobile-profile-section mobile-profile-recent" id="mobile-profile-recent">
          <div className="mobile-profile-section-heading"><h2>最近发布</h2><button type="button" onClick={() => void handleTabChange("posts")}>查看全部 <Icon name="chevron-right" size={15} /></button></div>
          {loading ? <div className="mobile-recent-card mobile-recent-loading"><span className="feed-spinner" /></div> : items.length ? <div className="mobile-recent-card">{items.slice(0, 2).map((item) => <Link key={item.id} href={`/post/${encodeURIComponent(item.id)}`} className="mobile-recent-item"><span className="mobile-recent-icon"><Icon name="message" size={20} /></span><span><strong>{item.title}</strong><small>{item.communityName} · {relativeTime(item.activityAt || item.createdAt)} · {item.commentCount} 回复</small></span><Icon name="chevron-right" size={17} /></Link>)}</div> : <div className="mobile-recent-card mobile-recent-empty"><span className="mobile-recent-icon"><Icon name="message" size={21} /></span><div><strong>还没有发布过帖子</strong><small>分享你的第一篇内容吧。</small></div><button type="button" onClick={() => router.push("/publish")}>去发布</button></div>}
        </section>

        <p className="mobile-profile-slogan">圣杯酱 · 把真实的玩具体验留在这里</p>
      </section>

      <main className="page-frame workbench-page desktop-workbench" style={{ maxWidth: 960, margin: "0 auto", padding: "24px 16px 80px" }}>
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
          <div className="workbench-stat-card workbench-stat-points">
            <button
              type="button"
              className="workbench-points-link"
              onClick={() => router.push("/points")}
              title="进入积分中心"
            >
              <div className="workbench-points-val">
                <strong style={{ color: "#d97706" }}>{points === null ? (pointsError ? "暂时无法获取" : "加载中…") : compactCount(points)}</strong>
                <Icon name="chevron-right" size={16} />
              </div>
              <span className="workbench-stat-lbl">我的积分 →</span>
            </button>
            {pointsError && (
              <button
                type="button"
                className="workbench-points-retry"
                onClick={() => setSummaryRetry((value) => value + 1)}
              >
                重新加载积分
              </button>
            )}
          </div>
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

      <footer className="profile-version-footer desktop-workbench" style={{ textAlign: "center", padding: "16px 0 24px" }}>
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
