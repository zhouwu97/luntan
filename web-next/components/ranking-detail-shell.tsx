"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "./site-header";
import { Icon } from "./icons";
import { MediaImage } from "./media-image";
import { UserAvatar } from "./user-avatar";
import { useSession } from "./session-provider";
import { compactCount, formatError, relativeTime } from "../lib/format";
import { createRankingToyComment, getRankingToyDetail, setRankingToyOwned, setRankingToyWant } from "../lib/api/forum";
import type { RankingToyComment, RankingToyDetail } from "../types/forum";

function scoreText(score: number) {
  return score % 1 === 0 ? String(score) : score.toFixed(1);
}

export function RankingDetailShell({ id }: { id: string }) {
  const router = useRouter();
  const { user } = useSession();
  const [detail, setDetail] = useState<RankingToyDetail | null>(null);
  const [sort, setSort] = useState<"weight" | "latest">("weight");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [wanted, setWanted] = useState(false);
  const [owned, setOwned] = useState(false);
  const [comment, setComment] = useState("");
  const [commentBusy, setCommentBusy] = useState(false);
  const [commentError, setCommentError] = useState("");

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    void getRankingToyDetail(id, sort)
      .then((nextDetail) => {
        if (!active) return;
        setDetail(nextDetail);
        setWanted(Boolean(nextDetail.viewerState?.wanted));
        setOwned(Boolean(nextDetail.viewerState?.owned));
      })
      .catch((requestError: unknown) => {
        if (active) setError(formatError(requestError, "商品详情暂时无法加载，请稍后再试"));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => { active = false; };
  }, [id, sort]);

  async function toggleWanted() {
    if (!detail) return;
    const next = !wanted;
    setWanted(next);
    try {
      await setRankingToyWant(detail.id, next);
      if (next) router.push(`/wishlist?id=${encodeURIComponent(detail.id)}`);
    } catch (requestError) {
      setWanted(!next);
      if (!user) router.push("/login");
      else setError(formatError(requestError, "想冲状态保存失败，请稍后重试"));
    }
  }

  async function toggleOwned() {
    if (!detail) return;
    const next = !owned;
    setOwned(next);
    try {
      await setRankingToyOwned(detail.id, next);
    } catch (requestError) {
      setOwned(!next);
      if (!user) router.push("/login");
      else setError(formatError(requestError, "购买状态保存失败，请稍后重试"));
    }
  }

  async function submitComment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!detail || !comment.trim() || commentBusy) return;
    if (!user) {
      router.push("/login");
      return;
    }
    setCommentBusy(true);
    setCommentError("");
    try {
      const next = await createRankingToyComment(detail.id, comment.trim());
      setDetail((current) => current ? { ...current, comments: [next, ...current.comments], ratingCount: current.ratingCount + 1 } : current);
      setComment("");
    } catch (requestError) {
      setCommentError(formatError(requestError, "评价发送失败，请稍后重试"));
    } finally {
      setCommentBusy(false);
    }
  }

  async function share() {
    const url = window.location.href;
    if (navigator.share) {
      await navigator.share({ title: detail?.name || "榜单商品", url }).catch(() => undefined);
    } else {
      await navigator.clipboard?.writeText(url);
    }
  }

  if (loading && !detail) {
    return <><SiteHeader className="ranking-detail-site-header" /><main className="page-frame"><div className="detail-skeleton"><div /><div /><div /></div></main></>;
  }
  if (!detail) {
    return <><SiteHeader className="ranking-detail-site-header" /><main className="page-frame"><div className="empty-state"><h1>商品不存在</h1><p>{error || "这条榜单商品可能已下架。"}</p><button type="button" className="primary-link" onClick={() => router.push("/ranking")}>返回榜单</button></div></main></>;
  }

  return (
    <>
      <SiteHeader className="ranking-detail-site-header" />
      <div className="ranking-detail-mobile-header"><button type="button" aria-label="返回" onClick={() => router.back()}><Icon name="chevron-left" size={22} /></button><Icon name="box" size={18} /><button type="button" aria-label="分享" onClick={() => void share()}><Icon name="arrow-up-right" size={20} /></button></div>
      <main className="page-frame ranking-detail-frame">
        <button type="button" className="back-link ranking-detail-desktop-back" onClick={() => router.back()}><Icon name="chevron-left" size={17} />返回榜单</button>
        {error && <div className="data-note" role="status">{error}</div>}
        <section className="ranking-detail-card">
          <div className="ranking-detail-product">
            <div className="ranking-detail-cover"><MediaImage sources={[detail.coverUrl, detail.heroUrl]} alt={detail.name} loading="eager" /></div>
            <div className="ranking-detail-product-copy"><h1>{detail.name}</h1><p>{detail.merchant}{detail.releaseYear ? ` · ${detail.releaseYear}` : ""}</p><div className="ranking-detail-tags">{detail.tags.slice(0, 3).map((tag) => <span key={tag}>#{tag}</span>)}</div></div>
          </div>
          <p className="ranking-detail-description">{detail.description || "暂无产品介绍"}</p>
          <RatingSummary detail={detail} />
          <div className="ranking-detail-actions"><button type="button" className={`ranking-want-button${wanted ? " active" : ""}`} onClick={() => void toggleWanted()}><Icon name="heart" size={18} />{wanted ? "已想冲" : "想冲"}<small>{compactCount(detail.wantCount)} 人想冲</small></button><button type="button" className={`ranking-owned-button${owned ? " active" : ""}`} onClick={() => void toggleOwned()}><Icon name="sparkle" size={17} />{owned ? "已买过" : "买过"}<small>{detail.ratingCount} 人评分</small></button></div>
        </section>
        <section className="ranking-reviews-section">
          <div className="ranking-reviews-heading"><h2>评价 <span>{detail.ratingCount}</span></h2><div><button type="button" className={sort === "weight" ? "active" : ""} onClick={() => setSort("weight")}>按权重排序</button><button type="button" className={sort === "latest" ? "active" : ""} onClick={() => setSort("latest")}>最新</button></div></div>
          <div className="ranking-review-list">{detail.comments.map((item) => <RankingReview key={item.id} item={item} />)}</div>
          {detail.commentsHasMore && <button type="button" className="load-more-button">加载更多评价</button>}
        </section>
        <form className="ranking-detail-composer" onSubmit={submitComment}><input value={comment} onChange={(event) => setComment(event.target.value)} onFocus={() => { if (!user) router.push("/login"); }} placeholder="来，说点什么吧!" aria-label="发表评价" /><span>{detail.ratingCount}</span><button type="submit" aria-label="发送评价" disabled={commentBusy}><Icon name="message" size={18} /></button>{commentError && <div className="form-error">{commentError}</div>}</form>
      </main>
    </>
  );
}

function RatingSummary({ detail }: { detail: RankingToyDetail }) {
  const buckets = useMemo(() => [
    ["5", (detail.ratingDistribution["10"] || 0) + (detail.ratingDistribution["9"] || 0)],
    ["4", (detail.ratingDistribution["8"] || 0) + (detail.ratingDistribution["7"] || 0)],
    ["3", (detail.ratingDistribution["6"] || 0) + (detail.ratingDistribution["5"] || 0)],
    ["2", (detail.ratingDistribution["4"] || 0) + (detail.ratingDistribution["3"] || 0)],
    ["1", (detail.ratingDistribution["2"] || 0) + (detail.ratingDistribution["1"] || 0)],
  ] as const, [detail.ratingDistribution]);
  const max = Math.max(...buckets.map(([, value]) => value), 1);
  return <div className="ranking-rating-summary"><div className="ranking-rating-score"><span>酱友评分</span><strong>{scoreText(detail.score)}</strong><div>♥ ♥ ♥ ♥ ♥</div></div><div className="ranking-rating-bars">{buckets.map(([label, value]) => <div key={label}><span>{label}</span><i><b style={{ width: `${Math.max(2, value / max * 100)}%` }} /></i></div>)}</div></div>;
}

function RankingReview({ item }: { item: RankingToyComment }) {
  return <article className="ranking-review"><UserAvatar userId={item.author.id} name={item.author.nickname} url={item.author.avatarUrl} size="small" /><div className="ranking-review-copy"><div className="ranking-review-author"><strong>{item.author.nickname}</strong><span>Lv.{item.author.level || 1}</span>{item.rating != null && <em>♥ ♥ ♥ ♥ ♥ {item.rating}分</em>}<time>{relativeTime(item.createdAt)}</time></div><p>{item.content}</p><div className="ranking-review-actions"><button type="button"><Icon name="heart" size={15} />{item.likeCount}</button><button type="button">回复</button></div></div></article>;
}
