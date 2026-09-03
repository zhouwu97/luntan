"use client";

import Link from "next/link";
import { FormEvent, useEffect, useRef, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Icon } from "./icons";
import { compactCount } from "../lib/format";
import { useSession } from "./session-provider";
import { UserAvatar } from "./user-avatar";

const navItems = [
  { label: "首页", href: "/" },
  { label: "排行榜", href: "/ranking" },
  { label: "热门", href: "/?sort=hot" },
  { label: "活动", href: "/activities" },
];

export function SiteHeader({ home = false, className = "" }: { home?: boolean; className?: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { user, ready, unreadCount, signOut } = useSession();
  const [query, setQuery] = useState("");
  const [menuOpen, setMenuOpen] = useState(false);
  const searchInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    setQuery(searchParams.get("q") || "");
  }, [searchParams]);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        searchInputRef.current?.focus();
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  function submitSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const value = query.trim();
    if (!value) return;
    router.push(`/search?q=${encodeURIComponent(value)}`);
  }

  async function handleSignOut() {
    setMenuOpen(false);
    await signOut();
  }

  return (
    <header className={`site-header${home ? " home-site-header" : ""}${className ? ` ${className}` : ""}`}>
      <div className="header-inner">
        <Link href="/" className="brand" aria-label="圣杯酱首页">
          <span className="brand-mark">
            <img src="/app-icon.png" alt="圣杯酱" className="brand-icon-img" />
          </span>
          <span className="brand-word">圣杯酱</span>
          <span className="brand-dot" aria-hidden="true" />
        </Link>

        <nav className="desktop-nav" aria-label="主导航">
          {navItems.map((item) => {
            const isActive = item.label === "首页"
              ? pathname === "/" && searchParams.get("sort") !== "hot"
              : item.label === "热门"
                ? pathname === "/" && searchParams.get("sort") === "hot"
                : pathname === item.href;
            return (
              <Link key={item.label} href={item.href} className={`nav-link${isActive ? " active" : ""}`} aria-current={isActive ? "page" : undefined}>
                {item.label}
              </Link>
            );
          })}
        </nav>

        <form className="header-search" onSubmit={submitSearch} role="search">
          <button type="submit" className="search-submit" aria-label="搜索"><Icon name="search" size={18} /></button>
          <input
            ref={searchInputRef}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="搜索帖子 / 用户 / 板块 / 榜单"
            aria-label="搜索帖子、用户、板块或榜单"
          />
          <kbd className="header-search-kbd">Ctrl K</kbd>
        </form>

        <div className="header-actions">
          <button className="publish-button" type="button" aria-label="发布帖子" onClick={() => router.push(user ? "/publish" : "/login")}>
            <Icon name="plus" size={18} />
            <span>发布帖子</span>
          </button>
          <button className="icon-button notification-button" type="button" aria-label="通知" onClick={() => router.push(user ? "/notifications" : "/login")}>
            <Icon name="bell" size={20} />
            {user && unreadCount > 0 && <span className="notification-dot">{unreadCount > 99 ? "99+" : compactCount(unreadCount)}</span>}
          </button>
          {ready && user ? (
            <div className="profile-menu-wrap">
              <button type="button" className="profile-avatar-button" aria-label="打开个人菜单" onClick={() => setMenuOpen((value) => !value)}>
                <UserAvatar userId={user.id} name={user.nickname} url={user.avatarUrl} size="header" />
              </button>
              {menuOpen && (
                <div className="profile-menu">
                  <div className="profile-menu-name">{user.nickname}</div>
                  <div className="profile-menu-meta">Lv.{user.level || 1} · {user.accountType === "guest" ? "游客" : "已登录"}</div>
                  <button type="button" onClick={() => { setMenuOpen(false); router.push(`/user/${user.id}`); }}>个人主页</button>
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
