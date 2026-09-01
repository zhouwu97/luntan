"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { Icon } from "./icons";
import { initials } from "../lib/format";
import { useSession } from "./session-provider";

const navItems = [
  { label: "首页", href: "/" },
  { label: "排行榜", href: "/ranking" },
  { label: "热门", href: "/?sort=hot" },
  { label: "活动", href: "/?view=activity" },
];

export function SiteHeader() {
  const router = useRouter();
  const pathname = usePathname();
  const { user, ready, signOut } = useSession();
  const [query, setQuery] = useState("");
  const [menuOpen, setMenuOpen] = useState(false);

  function submitSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const value = query.trim();
    if (!value) return;
    router.push(`/?q=${encodeURIComponent(value)}`);
  }

  async function handleSignOut() {
    setMenuOpen(false);
    await signOut();
  }

  return (
    <header className="site-header">
      <div className="header-inner">
        <Link href="/" className="brand" aria-label="圣杯酱首页">
          <span className="brand-mark"><Icon name="trophy" size={23} /></span>
          <span className="brand-word">圣杯酱</span>
        </Link>

        <nav className="desktop-nav" aria-label="主导航">
          {navItems.map((item) => {
            const isActive = item.label === "首页" && pathname === "/";
            return (
              <Link key={item.label} href={item.href} className={`nav-link${isActive ? " active" : ""}`}>
                {item.label}
              </Link>
            );
          })}
        </nav>

        <form className="header-search" onSubmit={submitSearch} role="search">
          <button type="submit" className="search-submit" aria-label="搜索"><Icon name="search" size={19} /></button>
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="搜索帖子 / 用户 / 板块"
            aria-label="搜索帖子、用户或板块"
          />
        </form>

        <div className="header-actions">
          <button className="publish-button" type="button" onClick={() => router.push(user ? "/publish" : "/login")}>
            <Icon name="plus" size={19} />
            <span>发布帖子</span>
          </button>
          <button className="icon-button notification-button" type="button" aria-label="通知" onClick={() => router.push(user ? "/notifications" : "/login")}>
            <Icon name="bell" size={21} />
            {user && <span className="notification-dot">3</span>}
          </button>
          {ready && user ? (
            <div className="profile-menu-wrap">
              <button
                type="button"
                className="avatar avatar-header"
                aria-label="打开个人菜单"
                onClick={() => setMenuOpen((value) => !value)}
              >
                {user.avatarUrl ? <img src={user.avatarUrl} alt="" /> : initials(user.nickname)}
              </button>
              {menuOpen && (
                <div className="profile-menu">
                  <div className="profile-menu-name">{user.nickname}</div>
                  <div className="profile-menu-meta">Lv.{user.level || 1} · {user.accountType === "guest" ? "游客" : "已登录"}</div>
                  <button type="button" onClick={() => router.push(`/user/${user.id}`)}>个人主页</button>
                  <button type="button" onClick={handleSignOut}>退出登录</button>
                </div>
              )}
            </div>
          ) : (
            <button className="login-link" type="button" onClick={() => router.push("/login")}>登录</button>
          )}
        </div>
      </div>
    </header>
  );
}
