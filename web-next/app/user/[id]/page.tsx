"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { SiteHeader } from "../../../components/site-header";
import { AppDownloadBanner } from "../../../components/app-download-banner";
import { BottomNav } from "../../../components/bottom-nav";
import { Icon } from "../../../components/icons";
import { UserAvatar } from "../../../components/user-avatar";
import { useSession } from "../../../components/session-provider";
import { getUserPosts, getUserProfile, setUserFollow } from "../../../lib/api/forum";
import { compactCount, formatError, relativeTime } from "../../../lib/format";
import type { ProfilePost, ProfileSummary, SessionUser } from "../../../types/forum";

function guestProfile(user: SessionUser | null): ProfileSummary {
  return {
    id: user?.id || "guest-local",
    username: user?.username || "guest_user",
    nickname: user?.nickname || "游客",
    level: 0,
    avatarUrl: user?.avatarUrl,
    bio: "游客可以浏览和评论，注册邮箱账号后即可发布帖子。",
    experience: user?.experience || 0,
    postCount: 0,
    commentCount: 0,
    likeReceivedCount: 0,
    followerCount: 0,
    followingCount: 0,
    isFollowing: false,
    canFollow: false,
  };
}

export default function UserPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const { user, ready, signOut } = useSession();
  const id = decodeURIComponent(params.id);
  const [profile, setProfile] = useState<ProfileSummary | null>(null);
  const [posts, setPosts] = useState<ProfilePost[]>([]);
  const [loading, setLoading] = useState(true);
  const [followBusy, setFollowBusy] = useState(false);
  const [error, setError] = useState("");
  const isSelf = id === "me" || user?.id === id;
  const isGuestSelf = id === "me" && (!user || user.accountType === "guest");

  useEffect(() => {
    if (!ready) return;
    if (id === "me" && (!user || user.accountType === "guest")) {
      setProfile(guestProfile(user));
      setPosts([]);
      setError("");
      setLoading(false);
      return;
    }
    let active = true;
    const profileId = id === "me" ? user?.id : id;
    if (!profileId) return;
    setLoading(true);
    setError("");
    void Promise.all([getUserProfile(profileId), getUserPosts(profileId)])
      .then(([nextProfile, nextPosts]) => {
        if (!active) return;
        setProfile(nextProfile);
        setPosts(nextPosts);
      })
      .catch((requestError: unknown) => {
        if (!active) return;
        setError(formatError(requestError, "个人主页暂时无法加载，请稍后再试"));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [id, ready, user]);

  async function toggleFollow() {
    if (!profile || followBusy) return;
    if (!user || user.accountType === "guest") {
      router.push(`/login?next=${encodeURIComponent("/user/me")}`);
      return;
    }
    const next = !profile.isFollowing;
    setFollowBusy(true);
    setProfile((curr) =>
      curr
        ? {
            ...curr,
            isFollowing: next,
            followerCount: Math.max(0, curr.followerCount + (next ? 1 : -1)),
          }
        : curr
    );
    try {
      await setUserFollow(profile.id, next);
    } catch (requestError) {
      setProfile((curr) =>
        curr
          ? {
              ...curr,
              isFollowing: !next,
              followerCount: Math.max(0, curr.followerCount + (next ? -1 : 1)),
            }
          : curr
      );
      setError(formatError(requestError, "关注操作失败，请稍后再试"));
    } finally {
      setFollowBusy(false);
    }
  }

  return (
    <>
      {/* 桌面端专用导航栏 */}
      <SiteHeader />

      {/* 移动端原型顶部 Header */}
      <header className="detail-head mobile-only">
        <button
          type="button"
          className="icon-btn"
          aria-label="返回首页"
          onClick={() => router.push("/")}
        >
          <Icon name="chevron-left" size={20} />
        </button>
        <span className="detail-community-name">{isSelf ? "我的" : profile?.nickname || "个人主页"}</span>
        <div style={{ width: 38 }} />
      </header>

      {/* 桌面端完整主页布局 */}
      <main className="page-frame profile-page-frame desktop-only">
        {loading ? (
          <div className="detail-skeleton">
            <div />
            <div />
          </div>
        ) : profile ? (
          <section className="profile-page">
            <div className="profile-hero">
              <UserAvatar
                userId={profile.id}
                name={profile.nickname}
                url={profile.avatarUrl}
                size="profile"
              />
              <div className="profile-copy">
                <div className="profile-title">
                  <h1>{profile.nickname}</h1>
                  <span className="level-label">Lv.{isGuestSelf ? 0 : profile.level || 1}</span>
                </div>
                <p>{profile.bio || "这个人还没有写简介。"}</p>
                <span className="profile-handle">
                  {profile.publicId ? `ID ${profile.publicId}` : profile.username}
                </span>
              </div>
              {!isSelf && (
                <button
                  type="button"
                  className={`outline-button profile-follow${profile.isFollowing ? " following" : ""}`}
                  disabled={followBusy}
                  onClick={toggleFollow}
                >
                  {followBusy ? "处理中…" : profile.isFollowing ? "已关注" : "+ 关注"}
                </button>
              )}
            </div>
            <div className="profile-stats">
              <span>
                <strong>{compactCount(profile.postCount)}</strong>
                <small>发帖</small>
              </span>
              <span>
                <strong>{compactCount(profile.commentCount)}</strong>
                <small>评论</small>
              </span>
              <span>
                <strong>{compactCount(profile.followerCount)}</strong>
                <small>粉丝</small>
              </span>
              <span>
                <strong>{compactCount(profile.followingCount)}</strong>
                <small>关注</small>
              </span>
            </div>
            {isGuestSelf && (
              <div className="profile-guest-banner">
                <div>
                  <strong>游客模式 · 当前累计 {profile.experience} EXP</strong>
                  <p>注册邮箱账号后保留当前经验和评论，并解锁等级与发布。</p>
                </div>
                <button
                  type="button"
                  className="primary-link"
                  onClick={() => router.push(`/login?next=${encodeURIComponent("/user/me")}`)}
                >
                  登录 / 注册
                </button>
              </div>
            )}
            <div className="profile-section-heading">
              <h2>{isSelf ? "我的帖子" : "TA 的帖子"}</h2>
              <span>{posts.length ? `${posts.length} 条` : "暂无内容"}</span>
            </div>
            {posts.length ? (
              <div className="profile-post-list">
                {posts.map((post) => (
                  <Link
                    key={post.id}
                    href={`/post/${encodeURIComponent(post.id)}`}
                    className="profile-post-row"
                  >
                    <div>
                      <span className="profile-post-community">{post.communityName}</span>
                      <h3>{post.title}</h3>
                      <p>{post.contentPreview || "（此帖子未提供文字内容）"}</p>
                    </div>
                    <div className="profile-post-meta">
                      <span>{relativeTime(post.createdAt)}</span>
                      <span>{compactCount(post.commentCount)} 回复</span>
                      <span>{compactCount(post.likeCount)} 赞</span>
                    </div>
                  </Link>
                ))}
              </div>
            ) : (
              <div className="profile-empty">
                <Icon name="sparkle" size={21} />
                <p>还没有公开帖子。</p>
              </div>
            )}
          </section>
        ) : (
          <div className="empty-state">
            <span className="empty-icon">
              <Icon name="user" size={24} />
            </span>
            <h1>个人主页不可用</h1>
            <p>{error || "这个用户可能不存在或已被隐藏。"}</p>
            <Link href="/" className="primary-link">
              返回首页
            </Link>
          </div>
        )}
      </main>

      {/* 移动端原型布局 */}
      <div className="mobile-only" style={{ padding: "16px 14px 100px" }}>
        {error && <div className="data-note">{error}</div>}

        {loading ? (
          <div className="loading-stack" style={{ padding: "20px 0" }}>
            <div className="skeleton-card" />
            <div className="skeleton-card short" />
          </div>
        ) : profile ? (
          <div>
            {/* 用户名片大卡 */}
            <div className="profile-hero-card">
              <UserAvatar
                userId={profile.id}
                name={profile.nickname}
                url={profile.avatarUrl}
                size="profile"
                className="profile-big-avatar"
              />
              <div className="profile-hero-meta">
                <div className="profile-hero-name">
                  <h2>{profile.nickname}</h2>
                  <span className="lv">Lv.{isGuestSelf ? 0 : profile.level || 1}</span>
                </div>
                <p className="profile-hero-sub">
                  {isGuestSelf
                    ? "游客模式 · 浏览与评论"
                    : profile.bio || `ID: ${profile.publicId || profile.username}`}
                </p>
              </div>
              {!isSelf && (
                <button
                  type="button"
                  className={`outline-button profile-follow${profile.isFollowing ? " following" : ""}`}
                  disabled={followBusy}
                  onClick={toggleFollow}
                >
                  {followBusy ? "处理中…" : profile.isFollowing ? "已关注" : "+ 关注"}
                </button>
              )}
            </div>

            {/* 三栏统计数据 */}
            <div className="profile-stats-grid">
              <div className="stat-box">
                <span className="stat-num blue">{compactCount(profile.postCount)}</span>
                <span className="stat-label">帖子</span>
              </div>
              <div className="stat-box">
                <span className="stat-num pink">{compactCount(profile.likeReceivedCount || 0)}</span>
                <span className="stat-label">获赞</span>
              </div>
              <div className="stat-box">
                <span className="stat-num orange">{compactCount(profile.commentCount || 0)}</span>
                <span className="stat-label">评论与收藏</span>
              </div>
            </div>

            {isGuestSelf && (
              <div className="profile-guest-card" style={{ marginTop: 14 }}>
                <div>
                  <strong>当前处于游客模式</strong>
                  <p>登录邮箱账号后即可发帖，并保留你的点赞与历史记录。</p>
                </div>
                <button
                  type="button"
                  className="primary-button"
                  onClick={() => router.push(`/login?next=${encodeURIComponent("/user/me")}`)}
                >
                  立即登录
                </button>
              </div>
            )}

            {/* 帖子列表 */}
            <div className="profile-section-heading" style={{ marginTop: 20 }}>
              <h3>{isSelf ? "我的发帖" : "TA 的帖子"}</h3>
              <span>{posts.length ? `${posts.length} 条` : "暂无"}</span>
            </div>

            <div className="profile-post-list">
              {posts.length ? (
                posts.map((post) => (
                  <Link
                    key={post.id}
                    href={`/post/${encodeURIComponent(post.id)}`}
                    className="profile-post-row"
                  >
                    <div className="row-content">
                      <span className="row-community">{post.communityName}</span>
                      <h4 className="row-title">{post.title}</h4>
                      <p className="row-desc">{post.contentPreview || "（图片或多媒体分享）"}</p>
                    </div>
                    <div className="row-meta">
                      <span>{relativeTime(post.createdAt)}</span>
                      <span>{compactCount(post.commentCount)} 回复</span>
                      <span>{compactCount(post.likeCount)} 赞</span>
                    </div>
                  </Link>
                ))
              ) : (
                <div className="empty-state" style={{ padding: "30px 0" }}>
                  <Icon name="sparkle" size={24} />
                  <p>还没有发布过帖子</p>
                </div>
              )}
            </div>

            {isSelf && !isGuestSelf && (
              <div style={{ marginTop: 24, textAlign: "center" }}>
                <button
                  type="button"
                  className="outline-button"
                  style={{ width: "100%", color: "var(--pink)", borderColor: "#ffd1df" }}
                  onClick={() => {
                    void signOut();
                    router.push("/");
                  }}
                >
                  退出登录
                </button>
              </div>
            )}
          </div>
        ) : null}

        {/* 底部下载 App 浮条（严格保留） */}
        <AppDownloadBanner />

        {/* 移动端底部导航栏 */}
        <BottomNav activeNav="profile" />
      </div>
    </>
  );
}
