"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { CommunityRail } from "./community-rail";
import { DiscoveryRail } from "./discovery-rail";
import { SiteHeader } from "./site-header";
import { AppDownloadBanner } from "./app-download-banner";
import { BottomNav } from "./bottom-nav";
import { FeedToolbar, type FeedSort, type LatestOrder } from "./feed-toolbar";
import { HomeCommunityTabs } from "./home-community-tabs";
import { HomeShortcuts } from "./home-shortcuts";
import { Icon } from "./icons";
import { MobileHomeHeader } from "./mobile-home-header";
import { PostCard } from "./post-card";
import { useSession } from "./session-provider";
import { useToast } from "./toast-context";
import { getCommunities, getFeed } from "../lib/api/forum";
import { readFeedCache, writeFeedCache, type FeedCacheOptions } from "../lib/feed-cache";
import { selectHomeCommunities } from "../lib/home-communities";
import { relativeTime } from "../lib/format";
import type { Community, Post } from "../types/forum";

const DEFAULT_HOME_COMMUNITY_ID = "community-campus";

export function normalizeSort(value: string | null): FeedSort {
  return value === "recommended" || value === "hot" ? value : "latest";
}

function cacheOptions(
  communityId: string,
  sort: FeedSort,
  latestOrder: LatestOrder,
  hasMedia: boolean,
  topic: string
): FeedCacheOptions {
  return { communityId, sort, latestOrder, hasMedia, topic: topic || undefined };
}

export function HomeShell() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { user } = useSession();
  const { showToast } = useToast();
  const requestedCommunityId = (searchParams.get("community") || "").trim();
  const query = (searchParams.get("q") || "").trim();
  const topic = (searchParams.get("topic") || "").trim();

  const [communities, setCommunities] = useState<Community[]>([]);
  const [activeCommunityId, setActiveCommunityId] = useState(requestedCommunityId || DEFAULT_HOME_COMMUNITY_ID);
  const [sort, setSort] = useState<FeedSort>(() => normalizeSort(searchParams.get("sort")));
  const [latestOrder, setLatestOrder] = useState<LatestOrder>("comment");
  const [hasMedia, setHasMedia] = useState(false);
  const [filterOpen, setFilterOpen] = useState(false);
  const [posts, setPosts] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [nextCursor, setNextCursor] = useState<string>();
  const [hasMore, setHasMore] = useState(false);
  const [error, setError] = useState("");
  const [communityError, setCommunityError] = useState("");
  const [refreshVersion, setRefreshVersion] = useState(0);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => {
    const rawSort = searchParams.get("sort");
    setSort(normalizeSort(rawSort));
    setHasMedia(searchParams.get("media") === "1");
    setActiveCommunityId(searchParams.get("community") || DEFAULT_HOME_COMMUNITY_ID);

    if (rawSort === "featured") {
      const nextParams = new URLSearchParams(searchParams.toString());
      nextParams.set("sort", "latest");
      router.replace(`/?${nextParams.toString()}`, { scroll: false });
    }
  }, [router, searchParams]);

  useEffect(() => {
    let mounted = true;
    setCommunityError("");
    void getCommunities({ status: "active" })
      .then((items) => {
        if (!mounted) return;
        const visible = selectHomeCommunities(items);
        setCommunities(visible);
        setActiveCommunityId((current) => {
          if (visible.some((item) => item.id === current)) return current;
          const campus = visible.find(
            (item) => item.id === DEFAULT_HOME_COMMUNITY_ID || item.name.trim() === "酱紫社区"
          );
          return campus?.id || visible[0]?.id || DEFAULT_HOME_COMMUNITY_ID;
        });
      })
      .catch(() => {
        if (mounted) {
          setCommunities([]);
          setCommunityError("首页板块暂时无法加载，请稍后重试");
        }
      });
    return () => {
      mounted = false;
    };
  }, []);

  const activeCommunity = communities.find((community) => community.id === activeCommunityId);
  const currentCacheOptions = useMemo(
    () => cacheOptions(activeCommunityId, sort, latestOrder, hasMedia, topic),
    [activeCommunityId, hasMedia, latestOrder, sort, topic]
  );

  useEffect(() => {
    let mounted = true;
    const cached = readFeedCache(currentCacheOptions);
    setPosts(cached?.items || []);
    setNextCursor(cached?.nextCursor);
    setHasMore(cached?.hasMore === true);
    setLoading(true);
    setError("");

    void getFeed({
      sort,
      communityId: activeCommunityId,
      hasMedia,
      latestOrder,
      topic: topic || undefined,
    })
      .then((page) => {
        if (!mounted) return;
        setPosts(page.items);
        setNextCursor(page.nextCursor);
        setHasMore(page.hasMore);
        writeFeedCache(currentCacheOptions, page);
      })
      .catch(() => {
        if (!mounted) return;
        setPosts(cached?.items || []);
        setNextCursor(cached?.nextCursor);
        setHasMore(cached?.hasMore === true);
        setError(
          cached
            ? sort === "recommended"
              ? "网络异常，显示上次推荐内容"
              : "网络异常，显示上次内容"
            : sort === "recommended"
            ? "推荐内容暂时无法加载"
            : "内容暂时无法加载"
        );
      })
      .finally(() => {
        if (mounted) setLoading(false);
      });
    return () => {
      mounted = false;
    };
  }, [activeCommunityId, currentCacheOptions, hasMedia, latestOrder, refreshVersion, sort, topic]);

  async function loadMore() {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    setError("");
    try {
      const page = await getFeed({
        sort,
        communityId: activeCommunityId,
        hasMedia,
        latestOrder,
        topic: topic || undefined,
        cursor: nextCursor,
      });
      setPosts((current) => {
        const knownIds = new Set(current.map((post) => post.id));
        const items = [...current, ...page.items.filter((post) => !knownIds.has(post.id))];
        writeFeedCache(currentCacheOptions, { ...page, items });
        return items;
      });
      setNextCursor(page.nextCursor);
      setHasMore(page.hasMore);
    } catch {
      setError("加载更多失败，请稍后再试");
    } finally {
      setLoadingMore(false);
    }
  }

  const visiblePosts = useMemo(() => {
    const source = hasMedia ? posts.filter((post) => post.media.length > 0) : posts;
    if (!query) return source;
    const normalizedQuery = query.toLocaleLowerCase();
    return source.filter((post) =>
      [post.title, post.content, post.author.nickname, post.community.name]
        .join(" ")
        .toLocaleLowerCase()
        .includes(normalizedQuery)
    );
  }, [hasMedia, posts, query]);

  function chooseCommunity(community?: Community) {
    if (!community) {
      setActiveCommunityId("");
      const nextParams = new URLSearchParams(searchParams.toString());
      nextParams.delete("community");
      router.replace(nextParams.toString() ? `/?${nextParams.toString()}` : "/", { scroll: false });
      return;
    }
    setActiveCommunityId(community.id);
    const nextParams = new URLSearchParams(searchParams.toString());
    if (community.id === DEFAULT_HOME_COMMUNITY_ID) nextParams.delete("community");
    else nextParams.set("community", community.id);
    router.replace(nextParams.toString() ? `/?${nextParams.toString()}` : "/", { scroll: false });
  }

  function chooseSort(value: FeedSort) {
    setSort(value);
    const nextParams = new URLSearchParams(searchParams.toString());
    if (value === "latest") nextParams.delete("sort");
    else nextParams.set("sort", value);
    router.replace(nextParams.toString() ? `/?${nextParams.toString()}` : "/", { scroll: false });
  }

  function chooseMedia(checked: boolean) {
    setHasMedia(checked);
    const nextParams = new URLSearchParams(searchParams.toString());
    if (checked) nextParams.set("media", "1");
    else nextParams.delete("media");
    router.replace(nextParams.toString() ? `/?${nextParams.toString()}` : "/", { scroll: false });
  }

  function handleFloatingRefresh() {
    if (refreshing) return;
    setRefreshing(true);
    showToast("已刷新到最新内容");
    setRefreshVersion((v) => v + 1);
    if (typeof window !== "undefined" && window.scrollY > 120) {
      window.scrollTo({ top: 0, behavior: "smooth" });
    }
    setTimeout(() => {
      setRefreshing(false);
    }, 600);
  }

  const emptyTitle = query
    ? "没有找到匹配内容"
    : sort === "recommended"
    ? "暂无推荐内容"
    : sort === "hot"
    ? "暂无热门内容"
    : "暂无最新内容";
  const emptyDescription = query
    ? "换个关键词，或者去社区里浏览更多分享。"
    : sort === "recommended"
    ? "管理员推荐的精选帖子会出现在这里"
    : "换一个筛选条件看看吧";

  return (
    <>
      {/* 桌面端专用导航栏 */}
      <SiteHeader home />

      {/* 移动端原型顶部 Header */}
      <MobileHomeHeader />

      <main className="page-frame home-page-frame">
        {/* 移动端专属快捷分段栏与入口金刚区 */}
        <div className="home-mobile-navigation">
          <HomeCommunityTabs
            communities={communities}
            activeId={activeCommunityId}
            onSelect={chooseCommunity}
          />
          <HomeShortcuts onFilterHot={() => chooseSort("hot")} />
        </div>

        {/* 响应式栅格：PC 宽屏为完整 3 列；移动端自适应为单列 */}
        <div className="home-grid">
          <div className="home-left-col">
            <CommunityRail
              communities={communities}
              activeId={activeCommunityId}
              onSelect={chooseCommunity}
            />
          </div>

          <section className="feed-column" aria-label={`${activeCommunity?.name || "首页"}帖子流`}>
            {communityError && <div className="data-note" role="status">{communityError}</div>}
            {error && <div className="data-note" role="status">{error}</div>}
            {query && <div className="data-note" role="status">正在显示“{query}”的匹配内容</div>}

            <FeedToolbar
              sort={sort}
              latestOrder={latestOrder}
              hasMedia={hasMedia}
              filterOpen={filterOpen}
              onSortChange={chooseSort}
              onLatestOrderChange={setLatestOrder}
              onFilterToggle={() => setFilterOpen((v) => !v)}
              onMediaChange={chooseMedia}
              canPublish={Boolean(user)}
            />

            {loading && !visiblePosts.length ? (
              <div className="loading-stack">
                <div className="skeleton-card" />
                <div className="skeleton-card short" />
              </div>
            ) : visiblePosts.length ? (
              <div className="post-list">
                {visiblePosts.map((post) => (
                  <PostCard
                    key={post.id}
                    post={post}
                    user={user}
                    contextMeta={
                      sort === "latest" && latestOrder === "comment" && post.activityAt
                        ? `最近回复 ${relativeTime(post.activityAt)}`
                        : undefined
                    }
                  />
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <span className="empty-icon">
                  <Icon name="sparkle" size={24} />
                </span>
                <h2>{emptyTitle}</h2>
                <p>{emptyDescription}</p>
              </div>
            )}

            {hasMore && (
              <button
                type="button"
                className="load-more-button"
                onClick={loadMore}
                disabled={loadingMore}
              >
                {loadingMore ? "正在加载…" : "加载更多"}
              </button>
            )}
          </section>

          <div className="home-right-col">
            <DiscoveryRail
              posts={visiblePosts}
              user={user}
              onLogin={() => router.push(user ? "/" : "/login")}
            />
          </div>
        </div>
      </main>

      {/* 移动端悬浮刷新按钮 */}
      <button
        type="button"
        className={`floating-refresh${refreshing ? " spinning" : ""}`}
        aria-label="刷新信息流"
        onClick={handleFloatingRefresh}
      >
        <Icon name="refresh" size={22} />
      </button>

      {/* 底部下载 App 窗口（移动端底部导航栏上方严格保留） */}
      <AppDownloadBanner />

      {/* 移动端底部导航栏 */}
      <BottomNav activeNav="home" />
    </>
  );
}
