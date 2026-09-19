"use client";

import { useSession } from "../../components/session-provider";
import { SiteHeader } from "../../components/site-header";
import { BottomNav } from "../../components/bottom-nav";
import { Icon } from "../../components/icons";
import { MobilePageHeader } from "../../components/mobile-page-header";
import { useEffect, useState } from "react";
import { ApiError } from "../../lib/api/client";
import { getAccountStatus, type AccountStatusData } from "../../lib/api/forum";

export default function AccountStatusPage() {
  const { user, ready, isRegistered } = useSession();
  const [data, setData] = useState<AccountStatusData | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    if (!ready || !isRegistered) return;
    void getAccountStatus().then(setData).catch((reason: unknown) => {
      setError(reason instanceof ApiError && reason.status === 403 ? "当前账号没有查看账号状态的权限" : reason instanceof Error ? reason.message : "账号状态加载失败");
    });
  }, [ready, isRegistered]);
  const statusLabel = data?.status === "active" ? "账号状态正常" : `账号状态：${data?.status || "未知"}`;
  return (
    <>
      <SiteHeader />
      <MobilePageHeader title="账号状态" />
      <main className="page-frame">
        <section className="feature-page account-status-page">
          {!ready || (isRegistered && !data && !error) ? <div className="simple-status-card"><p>正在加载账号状态…</p></div> : null}
          {!isRegistered ? <div className="simple-status-card"><h2>请先登录</h2><p>登录正式账号后才能查看处罚和限制记录。</p></div> : null}
          {error ? <div className="simple-status-card"><h2>暂时无法加载</h2><p>{error}</p><button type="button" className="primary-link" onClick={() => window.location.reload()}>重新加载</button></div> : null}
          {data ? <>
            <div className="account-status-card"><span className="account-status-icon"><Icon name={data.status === "active" ? "check" : "lock"} size={24} /></span><div><strong>{data.username || user?.username || "当前账号"}</strong><p>{statusLabel} · {data.punishments.length ? `${data.punishments.length} 条记录` : "无违规记录"}</p></div><span className="account-status-badge">{data.accountType === "official" ? "正式账号" : data.accountType || "正式账号"}</span></div>
            <div className="account-status-card account-status-email"><span className="account-status-icon"><Icon name="mail" size={20} /></span><div><strong>{data.email || user?.email || "未绑定邮箱"}</strong><p>{data.emailVerified ? "邮箱已完成验证" : "邮箱尚未验证"}</p></div>{data.emailVerified ? <Icon name="check" size={21} /> : null}</div>
          </> : null}
          <h2 className="account-status-heading">处罚与限制记录</h2>
          {data?.punishments.length ? <div className="account-status-list">{data.punishments.map((item) => <article className="account-status-card account-status-punishment" key={item.id}><span className="account-status-icon"><Icon name="lock" size={20} /></span><div><strong>{item.action || item.type || "账号处置"}</strong><p>{item.reason || "社区规则处置"}</p><small>{item.startsAt ? new Date(item.startsAt).toLocaleString("zh-CN") : ""}{item.endsAt ? ` · 至 ${new Date(item.endsAt).toLocaleString("zh-CN")}` : ""}</small></div>{item.appealable ? <span className="account-status-badge">可申诉</span> : null}</article>)}</div> : data ? <div className="simple-status-card account-status-empty"><span className="simple-status-icon"><Icon name="lock" size={26} /></span><p>当前没有处罚与限制记录</p></div> : null}
        </section>
      </main>
      <BottomNav activeNav="profile" />
    </>
  );
}
