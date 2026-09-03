"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Icon } from "./icons";
import { useSession } from "./session-provider";
import { UserAvatar } from "./user-avatar";

export function MobileHomeHeader() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { user, unreadCount } = useSession();
  const [query, setQuery] = useState("");

  useEffect(() => {
    setQuery(searchParams.get("q") || "");
  }, [searchParams]);

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const value = query.trim();
    if (value) {
      router.push(`/search?q=${encodeURIComponent(value)}`);
    }
  }

  return (
    <header className="mobile-head mobile-home-header">
      <button
        type="button"
        className="avatar-btn"
        aria-label="个人中心"
        onClick={() => router.push(user ? "/user/me" : "/login")}
      >
        <UserAvatar
          userId={user?.id}
          name={user?.nickname || "圣"}
          url={user?.avatarUrl}
          className="header-avatar"
        />
      </button>

      <form className="searchbox" onSubmit={submit} role="search">
        <Icon name="search" size={16} />
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="搜索帖子、用户、板块、榜单"
          aria-label="搜索"
        />
      </form>

      <button
        type="button"
        className="head-icon"
        aria-label="通知中心"
        onClick={() => router.push(user ? "/notifications" : "/login")}
      >
        <Icon name="bell" size={20} />
        {Boolean(user && unreadCount > 0) && <span className="notif-dot" />}
      </button>
    </header>
  );
}
