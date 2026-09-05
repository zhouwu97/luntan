"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { FeedToolbar, type FeedSort, type LatestOrder } from "./feed-toolbar";
import { Icon } from "./icons";
import { PostCard } from "./post-card";
import { SiteHeader } from "./site-header";
import { useSession } from "./session-provider";
import { useToast } from "./toast-context";
import { getCommunity, getFeed } from "../lib/api/forum";
import { readFeedCacheSnapshot, writeFeedCache } from "../lib/feed-cache";
import { relativeTime } from "../lib/format";
import type { Community, Post } from "../types/forum";

function normalizeSort(value: string | null): FeedSort {
  return value === "recommended" || value === "hot" ? value : "latest";
}

export function CommunityShell({ communityId }: { communityId: string }) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { user } = useSession();
  const { showToast } = useToast();
  const query = (searchParams.get("q") || "").trim();
  const [community, setCommunity] = useState<Community | null>(null);
  const [sort, setSort] = useState<FeedSort>(() => normalizeSort(searchParams.get("sort")));
  const [latestOrder, setLatestOrder] = useState<LatestOrder>("comment");
  const [hasMedia, setHasMedia] = useState(false);
  const [posts, setPosts] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const [nextCursor, setNextCursor] = useState<string>();
  const [error, setError] = useState("");
  const [communityError, setCommunityError] = useState("");
  const [filterOpen, setFilterOpen] = useState(false);
  const [refreshVersion, setRefreshVersion] = useState(0);

  useEffect(() => {
    const rawSort = searchParams.get("sort");
    setSort(normalizeSort(rawSort));
    setHasMedia(searchParams.get("media") === "1");
    if (rawSort === "featured") {
      const nextParams = new URLSearchParams(searchParams.toString());
      nextParams.set("sort", "latest");
      router.replace(`/community/${encodeURIComponent(communityId)}?${nextParams.toString()}`, { scroll: false });
    }
  }, [communityId, router, searchParams]);

  useEffect(() => {
    let active = true;
    setCommunity(null);
    setCommunityError("");
    void getCommunity(communityId)
      .then((item) => { if (active) setCommunity(item); })
      .catch(() => { if (active) setCommunityError("该社区暂时无法加载，请稍后重试"); });
    return () => { active = false; };
  }, [communityId]);

  const cacheOptions = useMemo(() => ({ communityId, sort, latestOrder, hasMedia, accountScope: user?.id }), [communityId, hasMedia, latestOrder, sort, user?.id]);

  useEffect(() => {
    let active = true;
    const snapshot = readFeedCacheSnapshot(cacheOptions);
    const cached = snapshot?.page || null;
    setPosts(cached?.items || []);
    setNextCursor(cached?.nextCursor);
    setHasMore(Boolean(cached?.hasMore));
    setLoading(!snapshot);
    setError("");

    if (snapshot?.isFresh) return () => { active = false; };

    void getFeed({ communityId, sort, latestOrder, hasMedia })
      .then((page) => {
        if (!active) return;
        setPosts(page.items);
        setNextCursor(page.nextCursor);
        setHasMore(page.hasMore);
        writeFeedCache(cacheOptions, page);
      })
      .catch(() => {
        if (!active) return;
        setError(cached ? "网络异常，显示上次加载的内容" : sort === "recommended" ? "推荐内容暂时无法加载" : "社区内容暂时无法加载");
      })
      .finally(() => { if (active) setLoading(false); });

    return () => { active = false; };
  }, [cacheOptions, communityId, hasMedia, latestOrder, refreshVersion, sort]);

  const visiblePosts = useMemo(() => {
    if (!query) return posts;
    const normalized = query.toLocaleLowerCase();
    return posts.filter((post) => `${post.title} ${post.content} ${post.author.nickname}`.toLocaleLowerCase().includes(normalized));
  }, [posts, query]);

  function updateQuery(nextSort: FeedSort, nextHasMedia = hasMedia) {
    const nextParams = new URLSearchParams(searchParams.toString());
    if (nextSort === "latest") nextParams.delete("sort");
    else nextParams.set("sort", nextSort);
    if (nextHasMedia) nextParams.set("media", "1");
    else nextParams.delete("media");
    const queryString = nextParams.toString();
    router.replace(`/community/${encodeURIComponent(communityId)}${queryString ? `?${queryString}` : ""}`, { scroll: false });
  }

  async function loadMore() {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const page = await getFeed({ communityId, sort, latestOrder, hasMedia, cursor: nextCursor });
      setPosts((current) => {
        const known = new Set(current.map((post) => post.id));
        const merged = [...current, ...page.items.filter((post) => !known.has(post.id))];
        writeFeedCache(cacheOptions, { ...page, items: merged });
        return merged;
      });
      setNextCursor(page.nextCursor);
      setHasMore(page.hasMore);
    } catch {
      setError("更多内容暂时无法加载");
    } finally {
      setLoadingMore(false);
    }
  }

  const title = community?.name || "社区";
  const emptyTitle = error ? "内容暂时无法展示" : sort === "recommended" ? "暂无推荐内容" : "这里还没有帖子";

  return (
    <>
      <SiteHeader className="community-detail-site-header" />
      <div className="community-mobile-header">
        <Link href="/" aria-label="返回首页"><Icon name="chevron-left" size={22} /></Link>
        <strong>{title}</strong>
        <button
          type="button"
          aria-label="更多操作"
          onClick={() => {
            if (typeof navigator !== "undefined" && navigator.clipboard) {
              void navigator.clipboard.writeText(window.location.href);
              showToast("已复制板块链接");
            }
          }}
        >
          <Icon name="more" size={19} />
        </button>
      </div>
      <main className="page-frame community-detail-page">
        <Link href="/communities" className="back-link"><Icon name="chevron-left" size={16} />全部社区</Link>
        {communityError && <div className="data-note" role="status">{communityError}</div>}
        {community && <section className="feature-hero compact-hero community-detail-hero"><div className="community-detail-heading"><span className="community-detail-icon"><Icon name="box" size={24} /></span><div><span className="feature-kicker">社区板块</span><h1>{community.name}</h1><p>{community.description || "和同好聊聊最近的新发现"}</p><div className="community-detail-stats"><span>{community.postCount} 帖子</span><span>{community.followerCount} 关注</span></div></div></div></section>}
        <section className="community-detail-feed" aria-label={`${title}帖子流`}>
          <FeedToolbar sort={sort} latestOrder={latestOrder} hasMedia={hasMedia} filterOpen={filterOpen} onSortChange={(nextSort) => updateQuery(nextSort)} onLatestOrderChange={setLatestOrder} onFilterToggle={() => setFilterOpen((value) => !value)} onMediaChange={(value) => updateQuery(sort, value)} canPublish={Boolean(user)} />
          {loading && visiblePosts.length > 0 && <div className="feed-refreshing" role="status">正在更新内容…</div>}
          {error && <div className="data-note" role="status">{error}</div>}
          {loading && !visiblePosts.length ? <div className="loading-stack community-detail-loading"><div className="skeleton-card" /><div className="skeleton-card short" /></div> : visiblePosts.length ? <div className="post-list community-detail-post-list">{visiblePosts.map((post, index) => <PostCard key={post.id} post={post} user={user} feedIndex={index} contextMeta={sort === "latest" && latestOrder === "comment" && post.activityAt ? `最近回复 ${relativeTime(post.activityAt)}` : undefined} />)}</div> : <div className="empty-state community-detail-empty"><span className="empty-icon"><Icon name="box" size={24} /></span><h2>{emptyTitle}</h2><p>{query ? `没有找到与“${query}”匹配的内容` : "稍后再来看看吧。"}</p></div>}
          {hasMore && <button type="button" className="load-more-button community-detail-more" onClick={loadMore} disabled={loadingMore}>{loadingMore ? "正在加载…" : "加载更多"}</button>}
        </section>
        <button type="button" className="mobile-refresh community-detail-refresh" aria-label="刷新社区内容" onClick={() => setRefreshVersion((value) => value + 1)}><Icon name="refresh" size={20} /></button>
      </main>
    </>
  );
}
