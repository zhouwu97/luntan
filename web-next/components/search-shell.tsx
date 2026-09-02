"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { SiteHeader } from "./site-header";
import { Icon } from "./icons";
import { searchForum } from "../lib/api/forum";
import { UserAvatar } from "./user-avatar";
import { formatError } from "../lib/format";
import type { SearchResults } from "../types/forum";

const emptyResults: SearchResults = { posts: [], users: [], communities: [], toys: [] };

export function SearchShell() {
  const params = useSearchParams();
  const query = (params.get("q") || "").trim();
  const [results, setResults] = useState<SearchResults>(emptyResults);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!query) {
      setResults(emptyResults);
      return;
    }
    let active = true;
    setLoading(true);
    setError("");
    void searchForum(query)
      .then((next) => {
        if (active) setResults(next);
      })
      .catch((requestError: unknown) => {
        if (active) setError(formatError(requestError, "搜索失败，请稍后再试"));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [query]);

  const total = results.posts.length + results.users.length + results.communities.length + results.toys.length;

  return (
    <>
      <SiteHeader />
      <main className="page-frame">
        <section className="feature-page">
          <div className="feature-hero compact-hero">
            <div>
              <span className="feature-kicker"><Icon name="search" size={16} /> 全站搜索</span>
              <h1>{query ? `“${query}”` : "搜索"}</h1>
              <p>直接查询 Go 后端 `/api/v1/search`，不再只过滤首页已加载帖子。</p>
            </div>
          </div>

          {error && <div className="data-note" role="status">{error}</div>}
          {loading && <div className="detail-skeleton"><div /><div /><div /></div>}
          {!loading && query && total === 0 && !error && <div className="empty-state feature-empty"><span className="empty-icon"><Icon name="search" size={24} /></span><h2>没有找到结果</h2><p>换个关键词试试。</p></div>}

          {!loading && results.posts.length > 0 && <ResultSection title={`帖子 ${results.posts.length}`}>
            {results.posts.map((post) => <Link key={post.id} href={`/post/${encodeURIComponent(post.id)}`} className="profile-post-row"><div><h3>{post.title}</h3><p>{post.contentPreview || "（无文字摘要）"}</p></div><div className="profile-post-meta"><span>{post.community?.name || "社区"}</span><span>{post.author?.nickname || "用户"}</span></div></Link>)}
          </ResultSection>}

          {!loading && results.users.length > 0 && <ResultSection title={`用户 ${results.users.length}`}>
            {results.users.map((user) => <Link key={user.id} href={`/user/${encodeURIComponent(user.id)}`} className="profile-post-row"><div style={{ display: "flex", alignItems: "center", gap: 12 }}><UserAvatar userId={user.id} name={user.nickname} url={user.avatarUrl} size="small" /><div><h3>{user.nickname}</h3><p>@{user.username} · Lv.{user.level || 1}</p></div></div></Link>)}
          </ResultSection>}

          {!loading && results.communities.length > 0 && <ResultSection title={`板块 ${results.communities.length}`}>
            {results.communities.map((community) => <Link key={community.id} href={`/?community=${encodeURIComponent(community.id)}`} className="profile-post-row"><div><h3>{community.name}</h3><p>{community.description || "暂无简介"}</p></div><div className="profile-post-meta"><span>{community.postCount} 帖子</span><span>{community.followerCount} 关注</span></div></Link>)}
          </ResultSection>}

          {!loading && results.toys.length > 0 && <ResultSection title={`榜单商品 ${results.toys.length}`}>
            {results.toys.map((toy) => <Link key={toy.id} href="/ranking" className="profile-post-row"><div><h3>{toy.name}</h3><p>{toy.description || toy.merchant || "榜单商品"}</p></div><div className="profile-post-meta"><span>{toy.score ? `${toy.score.toFixed(1)} 分` : "暂无评分"}</span><span>{toy.wantCount} 人想要</span></div></Link>)}
          </ResultSection>}
        </section>
      </main>
    </>
  );
}

function ResultSection({ title, children }: { title: string; children: React.ReactNode }) {
  return <section style={{ marginTop: 24 }}><div className="profile-section-heading"><h2>{title}</h2></div><div className="profile-post-list">{children}</div></section>;
}
