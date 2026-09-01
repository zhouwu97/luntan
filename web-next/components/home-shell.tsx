"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { CommunityRail } from "./community-rail";
import { DiscoveryRail } from "./discovery-rail";
import { Icon } from "./icons";
import { PostCard } from "./post-card";
import { SiteHeader } from "./site-header";
import { useSession } from "./session-provider";
import { fallbackCommunities, fallbackPosts } from "../lib/fallback-data";
import { getCommunities, getFeed } from "../lib/api/forum";
import { formatError } from "../lib/format";
import type { Community, Post } from "../types/forum";

type FeedSort = "recommended" | "latest" | "featured" | "hot";

const tabs: Array<{ label: string; value: FeedSort }> = [
  { label: "推荐", value: "recommended" },
  { label: "最新", value: "latest" },
  { label: "精华", value: "featured" },
  { label: "热门", value: "hot" },
];

function normalizeSort(value: string | null): FeedSort {
  return value === "latest" || value === "featured" || value === "hot" ? value : "recommended";
}

export function HomeShell() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { user } = useSession();
  const [communities, setCommunities] = useState<Community[]>([]);
  const [posts, setPosts] = useState<Post[]>([]);
  const [activeCommunity, setActiveCommunity] = useState<Community | undefined>();
  const [sort, setSort] = useState<FeedSort>(() => normalizeSort(searchParams.get("sort")));
  const [hasMedia, setHasMedia] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [filterOpen, setFilterOpen] = useState(false);
  const query = (searchParams.get("q") || "").trim();

  useEffect(() => {
    setSort(normalizeSort(searchParams.get("sort")));
  }, [searchParams]);

  useEffect(() => {
    let mounted = true;
    void getCommunities()
      .then((items) => {
        if (mounted) setCommunities(items.length ? items : fallbackCommunities);
      })
      .catch(() => {
        if (mounted) setCommunities(fallbackCommunities);
      });
    return () => {
      mounted = false;
    };
  }, []);

  useEffect(() => {
    let mounted = true;
    setLoading(true);
    setError("");
    void getFeed({ sort, communityId: activeCommunity?.id, hasMedia })
      .then((page) => {
        if (!mounted) return;
        setPosts(page.items.length ? page.items : fallbackPosts);
      })
      .catch((requestError: unknown) => {
        if (!mounted) return;
        setPosts(fallbackPosts);
        setError(formatError(requestError, "暂时使用本地缓存内容"));
      })
      .finally(() => {
        if (mounted) setLoading(false);
      });
    return () => {
      mounted = false;
    };
  }, [activeCommunity?.id, hasMedia, sort]);

  const visiblePosts = useMemo(() => {
    if (!query) return posts;
    const normalizedQuery = query.toLocaleLowerCase();
    return posts.filter((post) => [post.title, post.content, post.author.nickname, post.community.name]
      .join(" ")
      .toLocaleLowerCase()
      .includes(normalizedQuery));
  }, [posts, query]);

  function chooseSort(value: FeedSort) {
    setSort(value);
    const nextParams = new URLSearchParams(searchParams.toString());
    if (value === "recommended") nextParams.delete("sort");
    else nextParams.set("sort", value);
    router.replace(nextParams.toString() ? `/?${nextParams.toString()}` : "/", { scroll: false });
  }

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <div className="home-grid">
          <CommunityRail communities={communities} activeId={activeCommunity?.id} onSelect={setActiveCommunity} />
          <section className="feed-column" aria-label="帖子流">
            <div className="feed-toolbar">
              <div className="feed-tabs" role="tablist" aria-label="帖子排序">
                {tabs.map((tab) => (
                  <button key={tab.value} type="button" role="tab" aria-selected={sort === tab.value} className={`feed-tab${sort === tab.value ? " active" : ""}`} onClick={() => chooseSort(tab.value)}>
                    {tab.label}
                  </button>
                ))}
              </div>
              <div className="feed-tools">
                <button type="button" className={`filter-button${filterOpen ? " active" : ""}`} onClick={() => setFilterOpen((value) => !value)}><Icon name="filter" size={16} />筛选</button>
                {filterOpen && (
                  <div className="filter-popover">
                    <label><input type="checkbox" checked={hasMedia} onChange={(event) => setHasMedia(event.target.checked)} /> 只看有图片</label>
                  </div>
                )}
              </div>
            </div>
            {error && <div className="data-note" role="status">网络连接暂时不可用，已展示最近缓存的公开内容</div>}
            {query && <div className="data-note" role="status">正在显示“{query}”的匹配内容</div>}
            {loading && !visiblePosts.length ? (
              <div className="loading-stack"><div className="skeleton-card" /><div className="skeleton-card short" /></div>
            ) : visiblePosts.length ? (
              <div className="post-list">
                {visiblePosts.map((post) => <PostCard key={post.id} post={post} user={user} />)}
              </div>
            ) : (
              <div className="empty-state"><span className="empty-icon"><Icon name="sparkle" size={24} /></span><h2>{query ? "没有找到匹配内容" : "还没有帖子"}</h2><p>{query ? "换个关键词，或者去社区里浏览更多分享。" : "换一个社区或筛选条件看看吧。"}</p></div>
            )}
          </section>
          <DiscoveryRail posts={visiblePosts} user={user} onLogin={() => router.push(user ? "/" : "/login")} />
        </div>
      </main>
      <MobileNav user={Boolean(user)} onPublish={() => router.push(user ? "/publish" : "/login")} />
    </>
  );
}

function MobileNav({ user, onPublish }: { user: boolean; onPublish: () => void }) {
  const router = useRouter();
  return (
    <nav className="mobile-nav" aria-label="移动端导航">
      <button type="button" className="mobile-nav-item active" onClick={() => router.push("/")}><Icon name="trophy" size={22} /><span>首页</span></button>
      <button type="button" className="mobile-publish" onClick={onPublish}><Icon name="plus" size={28} /></button>
      <button type="button" className="mobile-nav-item" onClick={() => router.push(user ? "/user/me" : "/login")}><Icon name="user" size={22} /><span>我的</span></button>
    </nav>
  );
}
