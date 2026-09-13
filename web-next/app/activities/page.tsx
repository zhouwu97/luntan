"use client";

import { useEffect, useState } from "react";
import { SiteHeader } from "../../components/site-header";
import { BottomNav } from "../../components/bottom-nav";
import { Icon } from "../../components/icons";
import { getActivities } from "../../lib/api/forum";
import { formatError } from "../../lib/format";
import type { ActivityItem } from "../../types/forum";

const statusLabels: Record<string, string> = { upcoming: "未开始", active: "进行中", ended: "已结束" };

export default function ActivitiesPage() {
  const [items, setItems] = useState<ActivityItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  async function loadActivities() {
    setLoading(true);
    setError("");
    try {
      const nextItems = await getActivities();
      setItems(nextItems);
    } catch (requestError: unknown) {
      setError(formatError(requestError, "活动暂时无法加载，请稍后再试"));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    let active = true;
    void getActivities().then((nextItems) => {
      if (active) setItems(nextItems);
    }).catch((requestError: unknown) => {
      if (active) setError(formatError(requestError, "活动暂时无法加载，请稍后再试"));
    }).finally(() => {
      if (active) setLoading(false);
    });
    return () => {
      active = false;
    };
  }, []);

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <section className="feature-page activities-page">
          <div className="feature-hero">
            <div>
              <span className="feature-kicker"><Icon name="calendar" size={16} /> 社区活动</span>
              <h1>一起玩点新的</h1>
              <p>查看社区正在进行和即将开始的活动。</p>
            </div>
            {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
            <a href="/" className="outline-button feature-back">回到首页</a>
          </div>
          {error && <div className="data-note" role="status">{error}<button type="button" className="outline-button" onClick={() => void loadActivities()}>重新加载</button></div>}
          {loading ? (
            <div className="activity-list" aria-label="活动加载中"><div className="activity-skeleton" /><div className="activity-skeleton" /></div>
          ) : items.length ? (
            <div className="activity-list">{items.map((item) => <ActivityCard key={item.id} item={item} />)}</div>
          ) : (
            <div className="empty-state feature-empty">
              <span className="empty-icon"><Icon name="calendar" size={24} /></span><h2>暂时没有公开活动</h2><p>有新的活动时，我们会第一时间放在这里。</p>
              {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
              <a href="/" className="primary-link">去逛帖子</a>
            </div>
          )}
        </section>
      </main>
      <BottomNav activeNav="home" />
    </>
  );
}

function ActivityCard({ item }: { item: ActivityItem }) {
  const start = item.startAt ? new Date(item.startAt) : undefined;
  const end = item.endAt ? new Date(item.endAt) : undefined;
  const timeLabel = start && Number.isFinite(start.getTime())
    ? `${formatDate(start)}${end && Number.isFinite(end.getTime()) ? ` - ${formatDate(end)}` : ""}`
    : "时间待定";
  const status = statusLabels[item.status] || item.status;
  return (
    <a className="activity-card activity-card-link" href={`/activities/${encodeURIComponent(item.id)}`}>
      {item.coverUrl ? <img className="activity-cover" src={item.coverUrl} alt="" loading="lazy" /> : <div className="activity-cover activity-cover-empty"><Icon name="calendar" size={32} /></div>}
      <div className="activity-copy">
        <div className="activity-card-top"><span className={`activity-status activity-status-${item.status}`}>{status}</span><span className="activity-author">{item.authorName}</span></div>
        <h2>{item.title}</h2>
        {item.description && <p>{item.description}</p>}
        <div className="activity-meta"><span><Icon name="calendar" size={15} /> <time dateTime={item.startAt}>{timeLabel}</time></span>{item.location && <span><Icon name="arrow-up-right" size={15} /> {item.location}</span>}</div>
      </div>
    </a>
  );
}

function formatDate(value: Date): string {
  return new Intl.DateTimeFormat("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(value);
}
