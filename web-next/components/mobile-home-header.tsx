"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Icon } from "./icons";
import { useSession } from "./session-provider";
import { UserAvatar } from "./user-avatar";
import { compactCount } from "../lib/format";

export function MobileHomeHeader() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { user, unreadCount } = useSession();
  const [query, setQuery] = useState("");

  useEffect(() => setQuery(searchParams.get("q") || ""), [searchParams]);

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const value = query.trim();
    if (value) router.push(`/search?q=${encodeURIComponent(value)}`);
  }

  return (
    <header className="mobile-home-header">
      <button type="button" className="mobile-home-profile-button" aria-label="打开我的页面" onClick={() => router.push("/user/me")}>
        <UserAvatar userId={user?.id} name={user?.nickname || "游客"} url={user?.avatarUrl} size="header" />
      </button>
      <form className="mobile-home-search" onSubmit={submit} role="search"><Icon name="search" size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="搜索帖子 / 用户 / 板块 / 榜单" aria-label="搜索帖子、用户、板块或榜单" /></form>
      <button type="button" className="mobile-home-bell" aria-label="通知" onClick={() => router.push(user ? "/notifications" : "/login")}><Icon name="bell" size={21} />{user && unreadCount > 0 && <span className="notification-dot">{unreadCount > 99 ? "99+" : compactCount(unreadCount)}</span>}</button>
    </header>
  );
}
