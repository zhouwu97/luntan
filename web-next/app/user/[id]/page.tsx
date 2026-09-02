"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { SiteHeader } from "../../../components/site-header";
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
  const { user, ready } = useSession();
  const id = decodeURIComponent(params.id);
  const [profile, setProfile] = useState<ProfileSummary | null>(null);
  const [posts, setPosts] = useState<ProfilePost[]>([]);
  const [loading, setLoading] = useState(true);
  const [followBusy, setFollowBusy] = useState(false);
  const [error, setError] = useState("");
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
        if (active) setError(formatError(requestError, "个人主页暂时无法加载，请稍后再试"));
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
    setProfile((current) => current ? { ...current, isFollowing: next, followerCount: Math.max(0, current.followerCount + (next ? 1 : -1)) } : current);
    try {
      await setUserFollow(profile.id, next);
    } catch (requestError) {
      setProfile((current) => current ? { ...current, isFollowing: !next, followerCount: Math.max(0, current.followerCount + (next ? -1 : 1)) } : current);
      setError(formatError(requestError, "关注操作失败，请稍后再试"));
    } finally {
      setFollowBusy(false);
    }
  }

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        {loading ? <div className="detail-skeleton"><div /><div /></div> : profile ? <ProfileView profile={profile} posts={posts} isSelf={id === "me" || user?.id === profile.id} isGuest={isGuestSelf} onRequireAuth={() => router.push(`/login?next=${encodeURIComponent("/user/me")}`)} onFollow={toggleFollow} followBusy={followBusy} /> : <div className="empty-state"><span className="empty-icon"><Icon name="user" size={24} /></span><h1>个人主页不可用</h1><p>{error || "这个用户可能不存在或已被隐藏。"}</p><Link href="/" className="primary-link">返回首页</Link></div>}
        {error && profile && <div className="data-note" role="status">{error}</div>}
      </main>
    </>
  );
}

function ProfileView({ profile, posts, isSelf, isGuest, onRequireAuth, onFollow, followBusy }: { profile: ProfileSummary; posts: ProfilePost[]; isSelf: boolean; isGuest: boolean; onRequireAuth: () => void; onFollow: () => void; followBusy: boolean }) {
  return (
    <section className="profile-page">
      <div className="profile-hero"><UserAvatar userId={profile.id} name={profile.nickname} url={profile.avatarUrl} size="profile" /><div className="profile-copy"><div className="profile-title"><h1>{profile.nickname}</h1><span className="level-label">Lv.{isGuest ? 0 : (profile.level || 1)}</span></div><p>{profile.bio || "这个人还没有写简介。"}</p><span className="profile-handle">{profile.publicId ? `ID ${profile.publicId}` : profile.username}</span></div>{!isSelf && <button type="button" className={`outline-button profile-follow${profile.isFollowing ? " following" : ""}`} disabled={followBusy} onClick={onFollow}>{followBusy ? "处理中…" : profile.isFollowing ? "已关注" : "+ 关注"}</button>}</div>
      <div className="profile-stats"><span><strong>{compactCount(profile.postCount)}</strong><small>发帖</small></span><span><strong>{compactCount(profile.commentCount)}</strong><small>评论</small></span><span><strong>{compactCount(profile.followerCount)}</strong><small>粉丝</small></span><span><strong>{compactCount(profile.followingCount)}</strong><small>关注</small></span></div>
      {isGuest && <div className="profile-guest-banner"><div><strong>游客模式 · 当前累计 {profile.experience} EXP</strong><p>注册邮箱账号后保留当前经验和评论，并解锁等级与发布。</p></div><button type="button" className="primary-link" onClick={onRequireAuth}>登录 / 注册</button></div>}
      <div className="profile-section-heading"><h2>{isSelf ? "我的帖子" : "TA 的帖子"}</h2><span>{posts.length ? `${posts.length} 条` : "暂无内容"}</span></div>
      {posts.length ? <div className="profile-post-list">{posts.map((post) => <ProfilePostRow key={post.id} post={post} />)}</div> : <div className="profile-empty"><Icon name="sparkle" size={21} /><p>还没有公开帖子。</p></div>}
    </section>
  );
}

function ProfilePostRow({ post }: { post: ProfilePost }) {
  return <Link href={`/post/${encodeURIComponent(post.id)}`} className="profile-post-row"><div><span className="profile-post-community">{post.communityName}</span><h3>{post.title}</h3><p>{post.contentPreview || "（此帖子未提供文字内容）"}</p></div><div className="profile-post-meta"><span>{relativeTime(post.createdAt)}</span><span>{compactCount(post.commentCount)} 回复</span><span>{compactCount(post.likeCount)} 赞</span></div></Link>;
}
