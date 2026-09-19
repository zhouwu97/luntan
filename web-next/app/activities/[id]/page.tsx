import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { BottomNav } from "../../../components/bottom-nav";
import { Icon } from "../../../components/icons";
import { SiteHeader } from "../../../components/site-header";
import { getPublicActivity } from "../../../lib/server-activity";
import { publicSiteUrl } from "../../../lib/public-site";
import type { ActivityItem } from "../../../types/forum";

type ActivityPageProps = { params: Promise<{ id: string }> };

function decodeActivityID(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

export async function generateMetadata({ params }: ActivityPageProps): Promise<Metadata> {
  const { id } = await params;
  const activityID = decodeActivityID(id);
  const result = await getPublicActivity(activityID);
  if (result.status === "not_found") notFound();
  if (result.status === "unavailable") {
    return { title: "活动暂时无法加载 - 圣杯酱", robots: { index: false, follow: false } };
  }
  const activity = result.activity;
  const canonical = publicSiteUrl(`/activities/${encodeURIComponent(activity.id)}`);
  return {
    title: { absolute: `${activity.title} - 圣杯酱` },
    description: activity.description || "查看圣杯酱社区活动详情",
    alternates: { canonical },
    openGraph: { title: activity.title, description: activity.description || "社区活动详情", url: canonical, siteName: "圣杯酱", type: "article" },
  };
}

export default async function ActivityDetailPage({ params }: ActivityPageProps) {
  const { id } = await params;
  const activityID = decodeActivityID(id);
  const result = await getPublicActivity(activityID);
  if (result.status === "not_found") notFound();

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <section className="feature-page activity-detail-page">
          {/* 使用原生链接，避免部署环境下 RSC 预取失败阻塞返回操作。 */}
          {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
          <a href="/activities" className="back-link detail-back"><Icon name="chevron-left" size={17} /> 返回活动列表</a>
          {result.status === "unavailable" ? (
            <div className="data-note" role="alert">活动暂时无法加载，请稍后再试</div>
          ) : (
            <ActivityDetailContent item={result.activity} />
          )}
        </section>
      </main>
      <BottomNav activeNav={null} />
    </>
  );
}

function ActivityDetailContent({ item }: { item: ActivityItem }) {
  const start = item.startAt ? new Date(item.startAt) : undefined;
  const end = item.endAt ? new Date(item.endAt) : undefined;
  const timeLabel = start && Number.isFinite(start.getTime())
    ? `${formatDate(start)}${end && Number.isFinite(end.getTime()) ? ` - ${formatDate(end)}` : ""}`
    : "时间待定";
  const statusLabels: Record<string, string> = { upcoming: "未开始", active: "进行中", ended: "已结束" };

  return (
    <article className="activity-detail-card">
      {item.coverUrl ? <img className="activity-detail-cover" src={item.coverUrl} alt="" /> : <div className="activity-detail-cover activity-cover-empty"><Icon name="calendar" size={42} /></div>}
      <div className="activity-detail-copy">
        <div className="activity-card-top"><span className={`activity-status activity-status-${item.status}`}>{statusLabels[item.status] || item.status}</span><span className="activity-author">{item.authorName}</span></div>
        <h1>{item.title}</h1>
        <div className="activity-detail-meta"><span><Icon name="calendar" size={16} /> {timeLabel}</span>{item.location && <span><Icon name="arrow-up-right" size={16} /> {item.location}</span>}</div>
        {item.description && <p className="activity-detail-description">{item.description}</p>}
      </div>
    </article>
  );
}

function formatDate(value: Date): string {
  return new Intl.DateTimeFormat("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(value);
}
