"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { SiteHeader } from "../../components/site-header";
import { BottomNav } from "../../components/bottom-nav";
import { Icon } from "../../components/icons";
import { MobilePageHeader } from "../../components/mobile-page-header";
import { useSession } from "../../components/session-provider";
import { ApiError } from "../../lib/api/client";
import { getMyAppeals, type ModerationAppeal } from "../../lib/api/forum";

export default function AppealsPage() {
  const { ready, isRegistered } = useSession();
  const [items, setItems] = useState<ModerationAppeal[]>([]);
  const [error, setError] = useState("");
  useEffect(() => {
    if (!ready || !isRegistered) return;
    void getMyAppeals().then((page) => setItems(page.items)).catch((reason: unknown) => setError(reason instanceof ApiError && reason.status === 403 ? "当前账号暂时无法查看申诉记录" : reason instanceof Error ? reason.message : "申诉记录加载失败"));
  }, [ready, isRegistered]);
  return (
    <>
      <SiteHeader />
      <MobilePageHeader title="我的申诉" />
      <main className="page-frame">
        <section className="feature-page simple-status-page">
          <div className="feature-hero compact-hero"><div><span className="feature-kicker"><Icon name="edit" size={15} /> 社区管理</span><h1>我的申诉</h1><p>查看已提交的申诉及处理结果。</p></div><Icon name="chevron-right" size={22} /></div>
          {!ready ? <div className="simple-status-card"><p>正在加载申诉记录…</p></div> : null}
          {!isRegistered ? <div className="simple-status-card"><h2>请先登录</h2><p>登录后才能查看自己的申诉记录。</p><Link href="/login" className="primary-link">登录 / 注册</Link></div> : null}
          {error ? <div className="simple-status-card"><h2>暂时无法加载</h2><p>{error}</p><button type="button" className="primary-link" onClick={() => window.location.reload()}>重新加载</button></div> : null}
          {ready && isRegistered && !error && items.length === 0 ? <div className="simple-status-card"><span className="simple-status-icon"><Icon name="edit" size={26} /></span><h2>还没有申诉记录</h2><p>当你的内容或账号受到处置时，可以在此发起申诉复核。</p><Link href="/notifications?category=moderation" className="primary-link">查看处理通知</Link></div> : null}
          {items.length > 0 ? <div className="appeals-list">{items.map((item) => <article className="appeal-card" key={item.id}><div className="appeal-card-head"><strong>{item.targetTitle || item.reason || "社区内容申诉"}</strong><span className={`appeal-status appeal-status-${item.status}`}>{item.status === "pending" ? "处理中" : item.status === "approved" ? "已通过" : item.status === "rejected" ? "已驳回" : item.status}</span></div><p>{item.description || "未填写申诉说明"}</p><small>{item.createdAt ? new Date(item.createdAt).toLocaleString("zh-CN") : ""}{item.reviewerNote ? ` · ${item.reviewerNote}` : ""}</small></article>)}</div> : null}
        </section>
      </main>
      <BottomNav activeNav="profile" />
    </>
  );
}
