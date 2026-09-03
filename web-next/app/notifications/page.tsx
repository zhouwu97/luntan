"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "../../components/site-header";
import { Icon, type IconName } from "../../components/icons";
import { useSession } from "../../components/session-provider";
import { getNotifications, markAllNotificationsRead, markNotificationRead } from "../../lib/api/forum";
import { formatError, relativeTime } from "../../lib/format";
import type { ForumNotification } from "../../types/forum";

const tabs = [
  { label: "全部", value: "all" },
  { label: "互动", value: "interaction" },
  { label: "社区", value: "community" },
  { label: "处理", value: "moderation" },
];

export default function NotificationsPage() {
  const router = useRouter();
  const { user, ready, refreshUnreadCount } = useSession();
  const [category, setCategory] = useState("all");
  const [items, setItems] = useState<ForumNotification[]>([]);
  const [nextCursor, setNextCursor] = useState<string | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!ready || !user) return;
    let active = true;
    setLoading(true);
    setError("");
    setNextCursor(undefined);
    void getNotifications({ category: category === "all" ? undefined : category })
      .then((page) => {
        if (!active) return;
        setItems(page.items);
        setNextCursor(page.nextCursor);
        setHasMore(page.hasMore);
      })
      .catch((requestError: unknown) => {
        if (active) setError(formatError(requestError, "通知暂时无法加载，请稍后再试"));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [category, ready, user]);

  useEffect(() => {
    if (ready && !user) router.replace("/login");
  }, [ready, router, user]);

  async function loadMore() {
    if (!hasMore || !nextCursor || loadingMore) return;
    setLoadingMore(true);
    setError("");
    try {
      const page = await getNotifications({
        category: category === "all" ? undefined : category,
        cursor: nextCursor,
      });
      setItems((current) => {
        const known = new Set(current.map((item) => item.id));
        return [...current, ...page.items.filter((item) => !known.has(item.id))];
      });
      setNextCursor(page.nextCursor);
      setHasMore(page.hasMore);
    } catch (requestError) {
      setError(formatError(requestError, "加载更多通知失败"));
    } finally {
      setLoadingMore(false);
    }
  }

  async function readAll() {
    if (busy) return;
    setBusy(true);
    try {
      await markAllNotificationsRead();
      setItems((current) => current.map((item) => ({ ...item, isRead: true })));
      await refreshUnreadCount();
    } catch (requestError) {
      setError(formatError(requestError, "操作失败，请稍后再试"));
    } finally {
      setBusy(false);
    }
  }

  async function readOne(id: string) {
    try {
      await markNotificationRead(id);
      setItems((current) => current.map((item) => item.id === id ? { ...item, isRead: true } : item));
      await refreshUnreadCount();
    } catch {
      // 单条已读失败不阻断通知浏览，等待下一次刷新重试。
    }
  }

  if (!ready || !user) {
    return <><SiteHeader /><main className="page-frame"><div className="detail-skeleton"><div /><div /></div></main></>;
  }

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <section className="feature-page notifications-page">
          <div className="feature-hero compact-hero">
            <div><span className="feature-kicker"><Icon name="bell" size={16} /> 消息中心</span><h1>通知</h1><p>评论、点赞和社区动态都会在这里提醒你。</p></div>
            <button type="button" className="outline-button feature-back" disabled={busy} onClick={readAll}>{busy ? "处理中…" : "全部已读"}</button>
          </div>
          <div className="notification-tabs" role="tablist" aria-label="通知分类">
            {tabs.map((tab) => <button key={tab.value} type="button" role="tab" aria-selected={category === tab.value} className={category === tab.value ? "active" : ""} onClick={() => setCategory(tab.value)}>{tab.label}</button>)}
          </div>
          {error && <div className="data-note" role="status">{error}</div>}
          {loading ? <div className="notification-list"><div className="notification-skeleton" /><div className="notification-skeleton" /><div className="notification-skeleton" /></div> : items.length ? <><div className="notification-list">{groupNotifications(items).map((group) => <section className="notification-group" key={group.label}><h2>{group.label}</h2>{group.items.map((item) => <NotificationRow key={item.id} item={item} onRead={readOne} />)}</section>)}</div>{hasMore && <div style={{ display: "flex", justifyContent: "center", marginTop: 18 }}><button type="button" className="outline-button" disabled={loadingMore} onClick={loadMore}>{loadingMore ? "加载中…" : "加载更多"}</button></div>}</> : <div className="empty-state feature-empty"><span className="empty-icon"><Icon name="bell" size={24} /></span><h2>暂时没有通知</h2><p>有新的互动时，会在这里告诉你。</p></div>}
        </section>
      </main>
    </>
  );
}

function notificationHref(item: ForumNotification): string | undefined {
  if (!item.targetType || !item.targetId) return undefined;
  switch (item.targetType) {
    case "post":
      return `/post/${encodeURIComponent(item.targetId)}`;
    case "comment":
      return `/post/${encodeURIComponent(item.targetId)}#comments`;
    case "user":
      return `/user/${encodeURIComponent(item.targetId)}`;
    case "community":
      return `/?community=${encodeURIComponent(item.targetId)}`;
    case "ranking":
    case "toy":
      return `/ranking/${encodeURIComponent(item.targetId)}`;
    case "activity":
      return "/activities";
    default:
      return undefined;
  }
}

function NotificationRow({ item, onRead }: { item: ForumNotification; onRead: (id: string) => void }) {
  const href = notificationHref(item);
  const body = notificationBody(item);
  const kind = notificationKind(item);
  const content = <><span className={`notification-icon notification-icon-${kind}`}><Icon name={notificationIconName(item)} size={18} /></span><span className="notification-copy"><strong>{body.title}</strong>{body.content && <span>{body.content}</span>}<time dateTime={item.createdAt}>{relativeTime(item.createdAt)}</time></span>{!item.isRead && <span className="notification-unread" aria-label="未读" />}</>;
  return href ? <Link href={href} className={`notification-row${item.isRead ? "" : " unread"}`} onClick={() => { if (!item.isRead) void onRead(item.id); }}>{content}</Link> : <div className={`notification-row${item.isRead ? "" : " unread"}`} onClick={() => { if (!item.isRead) void onRead(item.id); }}>{content}</div>;
}

function groupNotifications(items: ForumNotification[]): Array<{ label: string; items: ForumNotification[] }> {
  const today = new Date();
  const groups = new Map<string, ForumNotification[]>();
  for (const item of items) {
    const date = new Date(item.createdAt);
    const isToday = Number.isFinite(date.getTime()) && date.getFullYear() === today.getFullYear() && date.getMonth() === today.getMonth() && date.getDate() === today.getDate();
    const label = isToday ? "今天" : "更早";
    groups.set(label, [...(groups.get(label) || []), item]);
  }
  return ["今天", "更早"].flatMap((label) => groups.has(label) ? [{ label, items: groups.get(label)! }] : []);
}

function notificationKind(item: ForumNotification): string {
  if (item.type.startsWith("moderation.") || item.type.startsWith("appeal.")) return "moderation";
  if (item.type.startsWith("community.") || item.type === "announcement" || item.type === "event") return "community";
  return "interaction";
}

function notificationIconName(item: ForumNotification): IconName {
  const kind = notificationKind(item);
  if (kind === "moderation") return "filter";
  if (kind === "community") return "sparkle";
  if (item.type === "comment.created" || item.type === "comment.replied" || item.type === "reply") return "message";
  if (item.type === "bookmark" || item.type === "post.bookmarked") return "bookmark";
  if (item.type === "follow" || item.type === "user.followed") return "user";
  return "heart";
}

function notificationBody(item: ForumNotification): { title: string; content: string } {
  const actor = item.actor.nickname || item.actor.username || "有人";
  const data = item.targetData;
  const customTitle = typeof data.title === "string" ? data.title : "";
  const contentValue = data.content ?? data.snippet ?? data.message ?? data.reason ?? data.post_title;
  const content = typeof contentValue === "string" ? contentValue : "";
  if (customTitle) return { title: customTitle, content };
  if (item.type === "follow" || item.type === "user.followed") return { title: `${actor} 关注了你`, content };
  if (item.type === "bookmark" || item.type === "post.bookmarked") return { title: `${actor} 收藏了你的帖子`, content };
  if (item.type === "like" || item.type === "post.liked") return { title: `${actor} 赞了你的内容`, content };
  if (item.type === "comment.created" || item.type === "comment.replied" || item.type === "reply") return { title: `${actor} 回复了你的内容`, content };
  if (item.type === "moderation.action") return { title: "账号或内容处理通知", content };
  if (item.type === "appeal.result") return { title: "申诉结果通知", content };
  return { title: "你有一条新通知", content };
}
