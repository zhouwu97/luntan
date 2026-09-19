"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useEffect, useRef, useState } from "react";
import { SiteHeader } from "../../components/site-header";
import { BottomNav } from "../../components/bottom-nav";
import { Icon } from "../../components/icons";
import { MobilePageHeader } from "../../components/mobile-page-header";
import { useSession } from "../../components/session-provider";
import { UserAvatar } from "../../components/user-avatar";
import { requestEmailCode, setPassword } from "../../lib/api/forum";

export default function SettingsPage() {
  const router = useRouter();
  const { user, ready, isRegistered, signOut } = useSession();
  const [privacyOpen, setPrivacyOpen] = useState(false);
  const [passwordOpen, setPasswordOpen] = useState(false);
  const [passwordMode, setPasswordMode] = useState<"current" | "email">("current");
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [emailCode, setEmailCode] = useState("");
  const [passwordMessage, setPasswordMessage] = useState("");
  const [passwordBusy, setPasswordBusy] = useState(false);
  const [codeBusy, setCodeBusy] = useState(false);
  const [codeCooldown, setCodeCooldown] = useState(0);
  const passwordDialogRef = useRef<HTMLElement>(null);

  useEffect(() => {
    if (!passwordOpen) return;
    const focusTarget = passwordDialogRef.current?.querySelector<HTMLInputElement>("input");
    focusTarget?.focus();
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !passwordBusy) setPasswordOpen(false);
    };
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [passwordOpen, passwordBusy]);

  useEffect(() => {
    if (codeCooldown <= 0) return;
    const timer = window.setInterval(() => setCodeCooldown((value) => Math.max(0, value - 1)), 1000);
    return () => window.clearInterval(timer);
  }, [codeCooldown]);

  function resetPasswordDialog() {
    setPasswordOpen(false);
    setPasswordMessage("");
    setCurrentPassword("");
    setNewPassword("");
    setConfirmPassword("");
    setEmailCode("");
    setPasswordMode("current");
  }

  async function handlePasswordSubmit(event?: FormEvent<HTMLFormElement>) {
    event?.preventDefault();
    if (passwordBusy) return;
    if (passwordMode === "current" && !currentPassword) {
      setPasswordMessage("请输入当前密码");
      return;
    }
    if (passwordMode === "email" && !emailCode) {
      setPasswordMessage("请输入邮箱验证码");
      return;
    }
    if (newPassword.length < 8) {
      setPasswordMessage("新密码至少 8 位");
      return;
    }
    if (newPassword !== confirmPassword) {
      setPasswordMessage("两次输入的新密码不一致");
      return;
    }
    setPasswordBusy(true);
    setPasswordMessage("");
    try {
      await setPassword({
        password: newPassword,
        currentPassword: passwordMode === "current" ? currentPassword : undefined,
        emailCode: passwordMode === "email" ? emailCode : undefined,
      });
      setPasswordMessage("密码已更新");
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      setEmailCode("");
    } catch (reason: unknown) {
      setPasswordMessage(reason instanceof Error ? reason.message : "密码更新失败");
    } finally {
      setPasswordBusy(false);
    }
  }

  async function handleRequestCode() {
    const email = user?.email;
    if (!email || codeBusy || codeCooldown > 0) return;
    setCodeBusy(true);
    setPasswordMessage("");
    try {
      const result = await requestEmailCode(email, "password_reset");
      setPasswordMessage(result.devCode ? `开发验证码：${result.devCode}` : "验证码已发送，请查收邮箱");
      setCodeCooldown(60);
    } catch (reason: unknown) {
      setPasswordMessage(reason instanceof Error ? reason.message : "验证码发送失败");
    } finally {
      setCodeBusy(false);
    }
  }

  if (!ready) {
    return (
      <>
        <SiteHeader />
        <MobilePageHeader title="设置" />
        <main className="page-frame">
          <section className="feature-page settings-page">
            <div className="feature-hero compact-hero settings-hero">
              <div><span className="feature-kicker">账号设置</span><h1>设置</h1><p>正在加载账号信息…</p></div>
              <div className="settings-hero-mark" aria-hidden="true"><Icon name="user" size={22} /></div>
            </div>
          </section>
        </main>
        <BottomNav activeNav="profile" />
      </>
    );
  }

  if (!user || !isRegistered) {
    return (
      <>
        <SiteHeader />
        <MobilePageHeader title="设置" />
        <main className="page-frame">
          <section className="feature-page settings-page">
            <div className="feature-hero compact-hero settings-hero"><div><span className="feature-kicker">账号设置</span><h1>游客模式</h1><p>登录或注册正式账号后，可以管理账号与通知偏好。</p></div><div className="settings-hero-action"><span className="settings-hero-mark" aria-hidden="true"><Icon name="user" size={22} /></span><Link href="/login" className="primary-link">登录 / 注册</Link></div></div>
            <div className="settings-guest-note"><Icon name="info" size={17} /><span>当前仍可浏览社区内容；登录后可同步收藏、消息与个人数据。</span></div>
            <div className="settings-guest-panel"><strong>游客也能使用</strong><span>浏览社区、查看通知和下载 App 不需要登录。</span><div><button type="button" onClick={() => router.push("/notifications")}><Icon name="bell" size={16} />通知中心</button><button type="button" onClick={() => router.push("/")}><Icon name="home" size={16} />返回首页</button></div></div>
          </section>
        </main>
        <BottomNav activeNav="profile" />
      </>
    );
  }

  return (
    <>
      <SiteHeader />
      <MobilePageHeader title="设置" />
      <main className="page-frame">
        <section className="feature-page settings-page">
          <div className="feature-hero compact-hero settings-hero">
            <div><span className="feature-kicker">账号设置</span><h1>设置</h1><p>管理你的账号入口与使用偏好。</p></div>
            <div className="settings-hero-action"><span className="settings-hero-mark" aria-hidden="true"><Icon name="user" size={22} /></span><button type="button" className="outline-button feature-back" onClick={() => router.push("/me")}>返回工作台</button></div>
          </div>
          <div className="settings-layout">
            <div className="settings-panel">
              <section className="settings-group"><div className="settings-section-heading"><div><strong>账号</strong><span>当前登录账号</span></div><Icon name="chevron-right" size={17} /></div><div className="settings-list" aria-label="设置选项"><button type="button" className="settings-row" onClick={() => router.push("/me")}><span className="settings-row-icon settings-row-icon-blue"><Icon name="user" size={18} /></span><span className="settings-row-copy"><strong>账号资料</strong><small>{user?.nickname || "当前账号"}</small></span><span className="settings-row-arrow" aria-hidden="true"><Icon name="chevron-right" size={17} /></span></button></div></section>
              <section className="settings-group"><div className="settings-section-heading"><div><strong>账号与安全</strong><span>登录与身份验证</span></div><Icon name="chevron-right" size={17} /></div><div className="settings-list" aria-label="账号与安全设置"><button type="button" className="settings-row" onClick={() => { setPasswordMessage(""); setPasswordOpen(true); }}><span className="settings-row-icon settings-row-icon-blue"><Icon name="lock" size={18} /></span><span className="settings-row-copy"><strong>修改密码</strong><small>使用当前密码或邮箱验证码验证身份</small></span><span className="settings-row-arrow" aria-hidden="true"><Icon name="chevron-right" size={17} /></span></button></div></section>
              <section className="settings-group"><div className="settings-section-heading"><div><strong>内容与隐私</strong><span>消息、数据与浏览习惯</span></div><Icon name="chevron-right" size={17} /></div><div className="settings-list" aria-label="内容与隐私设置"><button type="button" className="settings-row" onClick={() => router.push("/notifications")}><span className="settings-row-icon settings-row-icon-lilac"><Icon name="bell" size={18} /></span><span className="settings-row-copy"><strong>通知中心</strong><small>查看回复、点赞和社区消息</small></span><span className="settings-row-arrow" aria-hidden="true"><Icon name="chevron-right" size={17} /></span></button><button type="button" className="settings-row" onClick={() => setPrivacyOpen(true)}><span className="settings-row-icon settings-row-icon-mint"><Icon name="lock" size={18} /></span><span className="settings-row-copy"><strong>隐私与安全</strong><small>公开内容、账号数据与设备存储说明</small></span><span className="settings-row-arrow" aria-hidden="true"><Icon name="chevron-right" size={17} /></span></button><button type="button" className="settings-row" onClick={() => router.push("/me")}><span className="settings-row-icon settings-row-icon-violet"><Icon name="history" size={18} /></span><span className="settings-row-copy"><strong>浏览记录</strong><small>在我的工作台查看与管理历史内容</small></span><span className="settings-row-arrow" aria-hidden="true"><Icon name="chevron-right" size={17} /></span></button></div></section>
              <section className="settings-group"><div className="settings-section-heading"><div><strong>社区管理</strong><span>审核、申诉与账号限制</span></div><Icon name="chevron-right" size={17} /></div><div className="settings-list" aria-label="社区管理设置"><button type="button" className="settings-row" onClick={() => router.push("/governance")}><span className="settings-row-icon settings-row-icon-blue"><Icon name="info" size={18} /></span><span className="settings-row-copy"><strong>治理中心</strong><small>审核、申诉、推荐、活动与权限管理</small></span><span className="settings-row-arrow" aria-hidden="true"><Icon name="chevron-right" size={17} /></span></button><button type="button" className="settings-row" onClick={() => router.push("/appeals")}><span className="settings-row-icon settings-row-icon-orange"><Icon name="edit" size={18} /></span><span className="settings-row-copy"><strong>我的申诉</strong><small>查看已提交的申诉及处理结果</small></span><span className="settings-row-arrow" aria-hidden="true"><Icon name="chevron-right" size={17} /></span></button><button type="button" className="settings-row" onClick={() => router.push("/account-status")}><span className="settings-row-icon settings-row-icon-lilac"><Icon name="lock" size={18} /></span><span className="settings-row-copy"><strong>账号处罚详情</strong><small>当前限制、处罚原因与历史记录</small></span><span className="settings-row-arrow" aria-hidden="true"><Icon name="chevron-right" size={17} /></span></button></div></section>
              <section className="settings-group"><div className="settings-section-heading"><div><strong>关于</strong><span>下载、版本与登录状态</span></div><Icon name="chevron-right" size={17} /></div><div className="settings-list" aria-label="关于与账号操作"><button type="button" className="settings-row" onClick={() => router.push("/download")}><span className="settings-row-icon settings-row-icon-blue"><Icon name="download" size={18} /></span><span className="settings-row-copy"><strong>下载软件</strong><small>Android APK、版本说明与安装指引</small></span><span className="settings-row-arrow" aria-hidden="true"><Icon name="chevron-right" size={17} /></span></button><button type="button" className="settings-row danger" onClick={() => void signOut()}><span className="settings-row-icon settings-row-icon-orange"><Icon name="close" size={18} /></span><span className="settings-row-copy"><strong>退出登录</strong><small>退出后仍可继续以游客身份浏览</small></span><span className="settings-row-arrow" aria-hidden="true"><Icon name="chevron-right" size={17} /></span></button></div></section>
            </div>
            <aside className="settings-sidebar"><div className="settings-account-summary"><div className="settings-account-head"><UserAvatar userId={user.id} name={user.nickname} url={user.avatarUrl} size="large" /><div><strong>{user.nickname}</strong><span>{user.email || `@${user.username}`} · Lv.{user.level || 1}</span></div></div><div className="settings-account-stats"><span><strong>{user.experience ?? "—"}</strong><small>成长值</small></span><span><strong>Lv.{user.level || 1}</strong><small>等级</small></span><span><strong>正常</strong><small>账号状态</small></span></div></div><div className="settings-tip"><span className="settings-tip-icon"><Icon name="sparkle" size={18} /></span><strong>保持账号同步</strong><p>登录同一账号后，收藏、通知和浏览记录会在设备间保持一致。</p><button type="button" onClick={() => router.push("/me")}>查看工作台 <Icon name="arrow-up-right" size={14} /></button></div></aside>
          </div>
        </section>
      </main>
      <BottomNav activeNav="profile" />
      {privacyOpen && (
        <div className="settings-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target) setPrivacyOpen(false); }}>
          <section className="settings-dialog" role="dialog" aria-modal="true" aria-labelledby="settings-privacy-title">
            <div className="settings-dialog-header"><div><span className="settings-dialog-icon"><Icon name="lock" size={18} /></span><h2 id="settings-privacy-title">隐私与安全</h2></div><button type="button" aria-label="关闭" onClick={() => setPrivacyOpen(false)}><Icon name="close" size={18} /></button></div>
            <p>你的公开发帖、评论和点赞会按照社区规则展示。登录状态与本地缓存仅用于保持会话和提升加载速度。</p>
            <button type="button" className="primary-link settings-dialog-close" onClick={() => setPrivacyOpen(false)}>知道了</button>
          </section>
        </div>
      )}
      {passwordOpen && (
        <div className="settings-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target && !passwordBusy) resetPasswordDialog(); }}>
          <section ref={passwordDialogRef} className="settings-dialog settings-password-dialog" role="dialog" aria-modal="true" aria-labelledby="settings-password-title">
            <div className="settings-dialog-header"><div><span className="settings-dialog-icon"><Icon name="lock" size={18} /></span><h2 id="settings-password-title">修改密码</h2></div><button type="button" aria-label="关闭" onClick={resetPasswordDialog} disabled={passwordBusy}><Icon name="close" size={18} /></button></div>
            <form onSubmit={handlePasswordSubmit}>
              <div className="settings-password-tabs"><button type="button" className={passwordMode === "current" ? "active" : ""} onClick={() => { setPasswordMode("current"); setPasswordMessage(""); }}>当前密码验证</button><button type="button" className={passwordMode === "email" ? "active" : ""} onClick={() => { setPasswordMode("email"); setPasswordMessage(""); }}>邮箱验证码</button></div>
              {passwordMode === "current" ? <label>当前密码<input type="password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} autoComplete="current-password" /></label> : <label>邮箱验证码<div className="settings-code-field"><input value={emailCode} onChange={(event) => setEmailCode(event.target.value)} inputMode="numeric" autoComplete="one-time-code" /><button type="button" disabled={codeBusy || codeCooldown > 0 || !user.email} onClick={() => void handleRequestCode()}>{codeBusy ? "发送中" : codeCooldown > 0 ? `${codeCooldown}s 后重发` : "获取验证码"}</button></div></label>}
              <label>新密码<input type="password" value={newPassword} onChange={(event) => setNewPassword(event.target.value)} autoComplete="new-password" /></label>
              <label>确认新密码<input type="password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} autoComplete="new-password" /></label>
              {passwordMessage ? <p className="settings-dialog-message" role="status" aria-live="polite">{passwordMessage}</p> : null}
              <div className="settings-dialog-actions"><button type="button" className="outline-button" onClick={resetPasswordDialog} disabled={passwordBusy}>取消</button><button type="submit" className="primary-link" disabled={passwordBusy}>{passwordBusy ? "保存中…" : "保存密码"}</button></div>
            </form>
          </section>
        </div>
      )}
    </>
  );
}
