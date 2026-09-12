"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { SiteHeader } from "../../components/site-header";
import { BottomNav } from "../../components/bottom-nav";
import { useSession } from "../../components/session-provider";

export default function SettingsPage() {
  const router = useRouter();
  const { user, ready, signOut } = useSession();

  if (!ready) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame">
          <section className="feature-page">
            <div className="feature-hero compact-hero">
              <div><span className="feature-kicker">账号设置</span><h1>设置</h1><p>正在加载账号信息…</p></div>
            </div>
          </section>
        </main>
      </>
    );
  }

  if (!user) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame">
          <section className="feature-page">
            <div className="feature-hero compact-hero"><div><span className="feature-kicker">账号设置</span><h1>请先登录</h1><p>登录后可以管理账号与通知偏好。</p></div><Link href="/login" className="primary-link">登录</Link></div>
          </section>
        </main>
      </>
    );
  }

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <section className="feature-page">
          <div className="feature-hero compact-hero">
            <div><span className="feature-kicker">账号设置</span><h1>设置</h1><p>管理你的账号入口与使用偏好。</p></div>
            <button type="button" className="outline-button feature-back" onClick={() => router.push("/me")}>返回工作台</button>
          </div>
          <div className="settings-list" aria-label="设置选项">
            <button type="button" className="settings-row" onClick={() => router.push("/me")}><span><strong>账号资料</strong><small>{user?.nickname || "当前账号"}</small></span><span aria-hidden="true">›</span></button>
            <button type="button" className="settings-row" onClick={() => router.push("/notifications")}><span><strong>通知中心</strong><small>查看回复、点赞和社区消息</small></span><span aria-hidden="true">›</span></button>
            <button type="button" className="settings-row danger" onClick={() => void signOut()}><span><strong>退出登录</strong><small>退出后仍可继续以游客身份浏览</small></span><span aria-hidden="true">›</span></button>
          </div>
        </section>
      </main>
      <BottomNav activeNav="profile" />
    </>
  );
}
