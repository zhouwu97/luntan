"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "../../components/site-header";
import { AppDownloadBanner } from "../../components/app-download-banner";
import { BottomNav } from "../../components/bottom-nav";
import { Icon } from "../../components/icons";
import { UserAvatar } from "../../components/user-avatar";
import { useSession } from "../../components/session-provider";
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
  const { user, ready, signOut } = useSession();
  const [profile, setProfile] = useState<ProfileSummary | null>(null);
  const [points, setPoints] = useState<number>(0);
  const [activeTab, setActiveTab] = useState<TabKind>("posts");
  const [items, setItems] = useState<ProfilePost[]>([]);
  const [nextCursor, setNextCursor] = useState<string>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!ready) return;
    if (!user) {
      router.replace(`/login?next=${encodeURIComponent("/me")}`);
      return;
    }

    let active = true;
    setLoading(true);
    setError("");

    Promise.all([
      getUserProfile(user.id),
      getMyPoints().catch(() => ({ points: 0, experience: 0 })),
      getMyProfileList(activeTab),
    ])
      .then(([nextProfile, pointsData, listData]) => {
        if (!active) return;
        setProfile(nextProfile);
        setPoints(pointsData.points);
        setItems(listData.items);
        setNextCursor(listData.nextCursor);
        setHasMore(listData.hasMore);
      })
      .catch((err: unknown) => {
        if (!active) return;
        setError(formatError(err, "数据加载失败，请稍后重试"));
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [activeTab, ready, router, user]);

  async function handleTabChange(tab: TabKind) {
    if (tab === activeTab) return;
    setActiveTab(tab);
    setLoading(true);
    setError("");
    try {
      const res = await getMyProfileList(tab);
      setItems(res.items);
      setNextCursor(res.nextCursor);
      setHasMore(res.hasMore);
    } catch (err: unknown) {
      setError(formatError(err, "列表加载失败，请稍后重试"));
    } finally {
      setLoading(false);
    }
  }

  async function handleLoadMore() {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const res = await getMyProfileList(activeTab, nextCursor);
      setItems((curr) => [...curr, ...res.items]);
      setNextCursor(res.nextCursor);
      setHasMore(res.hasMore);
    } catch {
      setError("加载更多失败，请重试");
    } finally {
      setLoadingMore(false);
    }
  }

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

      <main className="page-frame" style={{ maxWidth: 960, margin: "0 auto", padding: "20px 16px 80px" }}>
        {/* 顶部个人卡片 & 工作台概览 */}
        <section
          style={{
            background: "#fff",
            border: "1px solid #e2e8f0",
            borderRadius: 20,
            padding: "24px 28px",
            boxShadow: "0 4px 20px rgba(0,0,0,0.03)",
            marginBottom: 20,
          }}
        >
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: 16 }}>
            <div style={{ display: "flex", gap: 16, alignItems: "center" }}>
              <UserAvatar userId={user.id} name={user.nickname} url={user.avatarUrl} size="large" />
              <div>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <h1 style={{ margin: 0, fontSize: 20, fontWeight: 800, color: "#0f172a" }}>{user.nickname}</h1>
                  <span className="level-label">Lv.{profile?.level || user.level || 1}</span>
                  {user.accountType === "guest" && (
                    <span style={{ fontSize: 11, background: "#fef3c7", color: "#92400e", padding: "2px 8px", borderRadius: 12 }}>
                      游客
                    </span>
                  )}
                </div>
                <p style={{ margin: "4px 0 0", fontSize: 13, color: "#64748b" }}>
                  @{user.username} · {profile?.bio || "暂无个人签名"}
                </p>
              </div>
            </div>

            <div style={{ display: "flex", gap: 10 }}>
              <Link href={`/user/${encodeURIComponent(user.id)}`} className="outline-button" style={{ fontSize: 13, padding: "6px 14px" }}>
                公开主页
              </Link>
              <button
                type="button"
                className="outline-button"
                style={{ fontSize: 13, padding: "6px 14px", color: "#ef4444", borderColor: "#fecaca" }}
                onClick={async () => {
                  await signOut();
                  router.push("/");
                }}
              >
                退出登录
              </button>
            </div>
          </div>

          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(100px, 1fr))",
              gap: 12,
              marginTop: 20,
              paddingTop: 16,
              borderTop: "1px solid #f1f5f9",
            }}
          >
            <div style={{ textAlign: "center" }}>
              <strong style={{ fontSize: 18, color: "#0f172a", display: "block" }}>{compactCount(profile?.postCount || 0)}</strong>
              <small style={{ color: "#64748b", fontSize: 12 }}>发帖</small>
            </div>
            <div style={{ textAlign: "center" }}>
              <strong style={{ fontSize: 18, color: "#0f172a", display: "block" }}>{compactCount(profile?.commentCount || 0)}</strong>
              <small style={{ color: "#64748b", fontSize: 12 }}>评论</small>
            </div>
            <div style={{ textAlign: "center" }}>
              <strong style={{ fontSize: 18, color: "#0f172a", display: "block" }}>{compactCount(profile?.followerCount || 0)}</strong>
              <small style={{ color: "#64748b", fontSize: 12 }}>粉丝</small>
            </div>
            <div style={{ textAlign: "center" }}>
              <strong style={{ fontSize: 18, color: "#0f172a", display: "block" }}>{compactCount(profile?.followingCount || 0)}</strong>
              <small style={{ color: "#64748b", fontSize: 12 }}>关注</small>
            </div>
            <div style={{ textAlign: "center" }}>
              <strong style={{ fontSize: 18, color: "#f59e0b", display: "block" }}>{compactCount(points)}</strong>
              <small style={{ color: "#64748b", fontSize: 12 }}>积分</small>
            </div>
          </div>
        </section>

        {/* 工作台分类 Tabs */}
        <div
          style={{
            display: "flex",
            gap: 8,
            overflowX: "auto",
            marginBottom: 16,
            paddingBottom: 4,
          }}
        >
          {TABS.map((tab) => (
            <button
              key={tab.kind}
              type="button"
              onClick={() => handleTabChange(tab.kind)}
              style={{
                padding: "8px 18px",
                borderRadius: 20,
                border: activeTab === tab.kind ? "1px solid #3b82f6" : "1px solid #e2e8f0",
                background: activeTab === tab.kind ? "#eff6ff" : "#fff",
                color: activeTab === tab.kind ? "#2563eb" : "#475569",
                fontWeight: 600,
                fontSize: 13,
                cursor: "pointer",
                whiteSpace: "nowrap",
                transition: "all .16s ease",
              }}
            >
              {tab.label}
            </button>
          ))}
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
              <div style={{ display: "flex", justifyContent: "center", marginTop: 20 }}>
                <button
                  type="button"
                  className="outline-button"
                  onClick={handleLoadMore}
                  disabled={loadingMore}
                  style={{ minWidth: 140 }}
                >
                  {loadingMore ? "正在加载…" : "加载更多"}
                </button>
              </div>
            )}
          </div>
        ) : (
          <div className="empty-state" style={{ background: "#fff", borderRadius: 16, padding: "48px 24px" }}>
            <Icon name="sparkle" size={28} />
            <h2 style={{ fontSize: 16, marginTop: 12 }}>暂无{TABS.find((t) => t.kind === activeTab)?.label}内容</h2>
            <p style={{ color: "#64748b", fontSize: 13 }}>去社区里发现好玩的内容并参与讨论吧。</p>
            <Link href="/" className="primary-link" style={{ marginTop: 12 }}>
              返回首页浏览
            </Link>
          </div>
        )}
      </main>

      <AppDownloadBanner />
      <BottomNav activeNav="profile" />
    </>
  );
}
