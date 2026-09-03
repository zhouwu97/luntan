"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Icon, type IconName } from "./icons";
import { UserAvatar } from "./user-avatar";
import { useSession } from "./session-provider";
import { getUserProfile } from "../lib/api/forum";
import type { Community, ProfileSummary } from "../types/forum";

const communityStyle: Record<string, { icon: IconName; tone: string }> = {
  酱紫社区: { icon: "trophy", tone: "lilac" },
  大型拆箱: { icon: "box", tone: "orange" },
  杂鱼日常: { icon: "sparkle", tone: "mint" },
};

export function CommunityRail({
  communities,
  activeId,
  onSelect,
}: {
  communities: Community[];
  activeId?: string;
  onSelect: (community: Community | undefined) => void;
}) {
  const router = useRouter();
  const { user, unreadCount } = useSession();
  const [profile, setProfile] = useState<ProfileSummary | null>(null);

  useEffect(() => {
    if (!user?.id) {
      setProfile(null);
      return;
    }
    let mounted = true;
    getUserProfile(user.id)
      .then((data) => {
        if (mounted) setProfile(data);
      })
      .catch(() => {
        // Fallback to basic session user if profile request fails
      });
    return () => {
      mounted = false;
    };
  }, [user?.id]);

  const greetingTime = () => {
    const hour = new Date().getHours();
    if (hour < 6) return "夜深了";
    if (hour < 11) return "早上好";
    if (hour < 14) return "中午好";
    if (hour < 18) return "下午好";
    return "晚上好";
  };

  return (
    <aside className="desktop-sidebar-rail" aria-label="社区侧边导航">
      {/* 个人状态卡片 */}
      <section className="profile-card">
        {user ? (
          <>
            <Link href={`/user/${user.id}`} className="profile-card-top" aria-label="查看个人主页">
              <UserAvatar userId={user.id} name={user.nickname} url={user.avatarUrl} size="large" className="profile-avatar-frame" />
              <div className="profile-card-info">
                <div className="profile-card-greeting">
                  <span className="profile-greeting-text">{greetingTime()}</span>
                  <span className="level-badge">Lv.{user.level || 1}</span>
                </div>
                <strong className="profile-card-name" title={user.nickname}>
                  {user.nickname}
                </strong>
                <span className="profile-card-hint">查看个人主页 &gt;</span>
              </div>
            </Link>

            <div className="profile-stats-grid" aria-label="用户数据统计">
              <Link href={`/user/${user.id}`} className="profile-stat-item">
                <strong>{profile?.postCount ?? 0}</strong>
                <span>帖子</span>
              </Link>
              <Link href={`/user/${user.id}`} className="profile-stat-item">
                <strong>{profile?.likeReceivedCount ?? 0}</strong>
                <span>获赞</span>
              </Link>
              <Link href={`/user/${user.id}`} className="profile-stat-item">
                <strong>{profile?.followerCount ?? 0}</strong>
                <span>粉丝</span>
              </Link>
            </div>
          </>
        ) : (
          <div className="profile-guest-card">
            <div className="profile-card-top" onClick={() => router.push("/login")} style={{ cursor: "pointer" }} role="button" tabIndex={0}>
              <UserAvatar name="杂鱼萌新" url="/default-avatar.webp" size="large" className="profile-avatar-frame" />
              <div className="profile-card-info">
                <div className="profile-card-greeting">
                  <span className="profile-greeting-text">{greetingTime()}</span>
                  <span className="level-badge">Lv.1</span>
                </div>
                <strong className="profile-card-name">
                  杂鱼萌新 (未登录)
                </strong>
                <span className="profile-card-hint">登录同步收藏与动态 &gt;</span>
              </div>
            </div>

            <div className="profile-stats-grid" aria-label="用户数据统计">
              <div className="profile-stat-item" onClick={() => router.push("/login")} style={{ cursor: "pointer" }}>
                <strong>-</strong>
                <span>帖子</span>
              </div>
              <div className="profile-stat-item" onClick={() => router.push("/login")} style={{ cursor: "pointer" }}>
                <strong>-</strong>
                <span>获赞</span>
              </div>
              <div className="profile-stat-item" onClick={() => router.push("/login")} style={{ cursor: "pointer" }}>
                <strong>-</strong>
                <span>粉丝</span>
              </div>
            </div>

            <button
              type="button"
              className="guest-login-btn"
              onClick={() => router.push("/login")}
            >
              立即登录
            </button>
          </div>
        )}
      </section>

      {/* 社区板块导航 */}
      <nav className="sidebar-nav-section" aria-label="社区板块">
        <div className="sidebar-section-kicker">COMMUNITY · 社区板块</div>
        <div className="sidebar-nav-list">
          <button
            type="button"
            className={`sidebar-nav-item${!activeId ? " active" : ""}`}
            onClick={() => onSelect(undefined)}
            aria-current={!activeId ? "page" : undefined}
          >
            <span className="sidebar-item-icon blue">
              <Icon name="grid" size={18} />
            </span>
            <span className="sidebar-item-label">
              <strong>社区首页</strong>
              <small>浏览全站动态精选</small>
            </span>
            <Icon name="chevron-right" size={15} className="sidebar-item-arrow" />
          </button>

          {communities.map((community) => {
            const style = communityStyle[community.name] ?? { icon: "sparkle" as IconName, tone: "blue" };
            const active = community.id === activeId;
            return (
              <button
                type="button"
                key={community.id}
                className={`sidebar-nav-item${active ? " active" : ""}`}
                onClick={() => onSelect(community)}
                aria-current={active ? "page" : undefined}
              >
                <span className={`sidebar-item-icon ${style.tone}`}>
                  <Icon name={style.icon} size={18} />
                </span>
                <span className="sidebar-item-label">
                  <strong>{community.name}</strong>
                  <small>{community.description || "和同好聊聊最近的新发现"}</small>
                </span>
                <Icon name="chevron-right" size={15} className="sidebar-item-arrow" />
              </button>
            );
          })}
        </div>

        <Link href="/communities" className="sidebar-browse-all">
          <span>浏览全部社区</span>
          <Icon name="arrow-up-right" size={14} />
        </Link>
      </nav>

      {/* 发现探索导航 */}
      <nav className="sidebar-nav-section" aria-label="发现探索">
        <div className="sidebar-section-kicker">DISCOVER · 发现探索</div>
        <div className="sidebar-nav-list">
          <Link href="/ranking" className="sidebar-nav-item">
            <span className="sidebar-item-icon gold">
              <Icon name="trophy" size={18} />
            </span>
            <span className="sidebar-item-label">
              <strong>圣杯排行榜</strong>
              <small>榜单评测与口碑排行</small>
            </span>
            <Icon name="chevron-right" size={15} className="sidebar-item-arrow" />
          </Link>

          <Link href="/activities" className="sidebar-nav-item">
            <span className="sidebar-item-icon orange">
              <Icon name="calendar" size={18} />
            </span>
            <span className="sidebar-item-label">
              <strong>活动专区</strong>
              <small>官方赛事与社区互动</small>
            </span>
            <Icon name="chevron-right" size={15} className="sidebar-item-arrow" />
          </Link>

          <Link href={user ? "/notifications" : "/login"} className="sidebar-nav-item">
            <span className="sidebar-item-icon lilac">
              <Icon name="bell" size={18} />
            </span>
            <span className="sidebar-item-label">
              <strong>我的消息</strong>
              <small>{unreadCount > 0 ? `${unreadCount} 条未读动态` : "回复与系统通知"}</small>
            </span>
            {unreadCount > 0 && <span className="sidebar-badge">{unreadCount}</span>}
          </Link>
        </div>
      </nav>

      {/* 底部醒目发布帖子按钮 */}
      <button
        type="button"
        className="sidebar-compose-button"
        onClick={() => router.push(user ? "/publish" : "/login")}
        aria-label="发布新帖"
      >
        <Icon name="edit" size={18} />
        <span>发布新帖</span>
      </button>
    </aside>
  );
}
