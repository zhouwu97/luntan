"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { BottomNav } from "../../../components/bottom-nav";
import { Icon } from "../../../components/icons";
import { SiteHeader } from "../../../components/site-header";
import { getActivity } from "../../../lib/api/forum";
import { formatError } from "../../../lib/format";
import type { ActivityItem } from "../../../types/forum";

const statusLabels: Record<string, string> = { upcoming: "未开始", active: "进行中", ended: "已结束" };

export default function ActivityDetailPage() {
  const params = useParams<{ id: string }>();
  const activityID = decodeURIComponent(params.id);
  const [item, setItem] = useState<ActivityItem | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    void getActivity(activityID).then((nextItem) => {
      if (active) setItem(nextItem);
    }).catch((requestError: unknown) => {
      if (active) setError(formatError(requestError, "活动暂时无法加载，请稍后再试"));
    }).finally(() => {
      if (active) setLoading(false);
    });
    return () => {
      active = false;
    };
  }, [activityID]);

  const start = item?.startAt ? new Date(item.startAt) : undefined;
  const end = item?.endAt ? new Date(item.endAt) : undefined;
  const timeLabel = start && Number.isFinite(start.getTime())
    ? `${formatDate(start)}${end && Number.isFinite(end.getTime()) ? ` - ${formatDate(end)}` : ""}`
    : "时间待定";

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <section className="feature-page activity-detail-page">
          {/* 使用原生链接，避免部署环境下 RSC 预取失败阻塞返回操作。 */}
          {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
          <a href="/activities" className="back-link detail-back"><Icon name="chevron-left" size={17} /> 返回活动列表</a>
          {loading ? <div className="loading-stack" style={{ padding: 40, textAlign: "center" }}>正在加载活动…</div> : error ? (
            <div className="data-note" role="alert">{error}</div>
          ) : !item ? (
            <div className="empty-state feature-empty"><span className="empty-icon"><Icon name="calendar" size={24} /></span><h1>活动不存在</h1><p>这项活动可能已下线或被删除。</p></div>
          ) : (
            <article className="activity-detail-card">
              {item.coverUrl ? <img className="activity-detail-cover" src={item.coverUrl} alt="" /> : <div className="activity-detail-cover activity-cover-empty"><Icon name="calendar" size={42} /></div>}
              <div className="activity-detail-copy">
                <div className="activity-card-top"><span className={`activity-status activity-status-${item.status}`}>{statusLabels[item.status] || item.status}</span><span className="activity-author">{item.authorName}</span></div>
                <h1>{item.title}</h1>
                <div className="activity-detail-meta"><span><Icon name="calendar" size={16} /> {timeLabel}</span>{item.location && <span><Icon name="arrow-up-right" size={16} /> {item.location}</span>}</div>
                {item.description && <p className="activity-detail-description">{item.description}</p>}
              </div>
            </article>
          )}
        </section>
      </main>
      <BottomNav activeNav="home" />
    </>
  );
}

function formatDate(value: Date): string {
  return new Intl.DateTimeFormat("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(value);
}
