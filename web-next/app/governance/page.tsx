"use client";

import { SiteHeader } from "../../components/site-header";
import { BottomNav } from "../../components/bottom-nav";
import { Icon } from "../../components/icons";
import { MobilePageHeader } from "../../components/mobile-page-header";
import { useEffect, useState } from "react";
import { ApiError } from "../../lib/api/client";
import { getModerationAppeals, getModerationCases } from "../../lib/api/forum";
import { useSession } from "../../components/session-provider";

const tools = [
  ["审核与用户处置", "举报、审核、隐藏恢复、禁言与封禁", "info"],
  ["申诉处理", "查看并处理用户对处罚的申诉", "edit"],
  ["首页推荐", "管理人工精选与推荐顺序", "trophy"],
  ["活动管理", "创建、编辑、发布与下架社区活动", "calendar"],
  ["玩具提交审核", "审核用户投稿的榜单玩具", "box"],
  ["兑换审核", "查看用户发帖与评论、审核积分兑换申请", "sparkle"],
] as const;

export default function GovernancePage() {
  const { ready, isRegistered } = useSession();
  const [caseCount, setCaseCount] = useState<number | null>(null);
  const [appealCount, setAppealCount] = useState<number | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    if (!ready || !isRegistered) return;
    void Promise.all([getModerationCases({ status: "pending", limit: 20 }), getModerationAppeals({ status: "pending", limit: 20 })])
      .then(([cases, appeals]) => { setCaseCount(cases.items.length); setAppealCount(appeals.items.length); })
      .catch((reason: unknown) => setError(reason instanceof ApiError && (reason.status === 401 || reason.status === 403) ? "当前账号没有治理中心权限" : reason instanceof Error ? reason.message : "治理数据加载失败"));
  }, [ready, isRegistered]);
  return (
    <>
      <SiteHeader />
      <MobilePageHeader title="治理中心" />
      <main className="page-frame">
        <section className="feature-page governance-page">
          <div className="governance-hero">
            <span className="governance-hero-icon"><Icon name="lock" size={25} /></span>
            <div><span className="feature-kicker">社区管理</span><h1>治理工作台</h1><p>超级管理员控制台 · 权限实时生效</p></div>
            <div className="governance-stats"><span><strong>{caseCount ?? "—"}</strong><small>待复核</small></span><span><strong>{caseCount ?? "—"}</strong><small>风险事件</small></span><span><strong>{appealCount ?? "—"}</strong><small>待申诉</small></span></div>
          </div>
          {error ? <div className="governance-notice"><Icon name="info" size={17} /><span>{error}</span></div> : null}
          <div className="governance-section-heading"><h2>内容审核与推荐</h2></div>
          <div className="governance-grid">{tools.map(([title, description, icon]) => <button key={title} type="button" className="governance-card"><span className="governance-card-icon"><Icon name={icon} size={18} /></span><span><strong>{title}</strong><small>{description}</small></span><Icon name="chevron-right" size={17} /></button>)}</div>
          <div className="governance-section-heading"><h2>账号与授权</h2></div>
          <div className="governance-grid governance-grid-secondary"><button type="button" className="governance-card"><span className="governance-card-icon"><Icon name="user" size={18} /></span><span><strong>用户管理</strong><small>查询账号、分页浏览、查看发布与处罚</small></span><Icon name="chevron-right" size={17} /></button><button type="button" className="governance-card"><span className="governance-card-icon"><Icon name="lock" size={18} /></span><span><strong>管理员管理</strong><small>角色授权、权限范围与操作记录</small></span><Icon name="chevron-right" size={17} /></button></div>
        </section>
      </main>
      <BottomNav activeNav="profile" />
    </>
  );
}
