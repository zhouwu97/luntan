"use client";

import { FormEvent, useEffect, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { SiteHeader } from "./site-header";
import { Icon } from "./icons";
import { MediaImage } from "./media-image";
import { UserAvatar } from "./user-avatar";
import { RankingCommentThreadSheet } from "./ranking-comment-thread-sheet";
import { useSession } from "./session-provider";
import { compactCount, formatError, relativeTime } from "../lib/format";
import {
  createRankingToyComment,
  getRankingToyComments,
  getRankingToyDetail,
  rateRankingToy,
  setRankingToyCommentLike,
  setRankingToyOwned,
  setRankingToyWant,
} from "../lib/api/forum";
import { writeRankingToyCache } from "../lib/ranking-client-cache";
import type { RankingToyComment, RankingToyDetail } from "../types/forum";

function scoreText(score: number) {
  return score % 1 === 0 ? String(score) : score.toFixed(1);
}

function safeRankingReturn(value: string | null) {
  if (!value || value.startsWith("//") || !value.startsWith("/ranking")) return "/ranking";
  return value;
}

function currentLocalPath(pathname: string, search: string) {
  return `${pathname}${search}`;
}

export function RankingDetailShell({ id }: { id: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { user } = useSession();
  const returnPath = safeRankingReturn(searchParams.get("from"));
  const [detail, setDetail] = useState<RankingToyDetail | null>(null);
  const [sort, setSort] = useState<"weight" | "latest">("weight");
  const [loading, setLoading] = useState(true);
  const [commentsLoading, setCommentsLoading] = useState(true);
  const [error, setError] = useState("");
  const [wanted, setWanted] = useState(false);
  const [owned, setOwned] = useState(false);
  const [comments, setComments] = useState<RankingToyComment[]>([]);
  const [commentsCursor, setCommentsCursor] = useState<string>();
  const [commentsHasMore, setCommentsHasMore] = useState(false);
  const [commentsLoadingMore, setCommentsLoadingMore] = useState(false);
  const [comment, setComment] = useState("");
  const [commentBusy, setCommentBusy] = useState(false);
  const [commentError, setCommentError] = useState("");
  const [threadRoot, setThreadRoot] = useState<RankingToyComment | null>(null);
  const [ratingOpen, setRatingOpen] = useState(false);
  const [ratingSelection, setRatingSelection] = useState(10);
  const [ratingBusy, setRatingBusy] = useState(false);
  const [likingCommentIds, setLikingCommentIds] = useState<Record<string, boolean>>({});

  useEffect(() => {
    let active = true;
    setLoading(true);
    setCommentsLoading(true);
    setComments([]);
    setCommentsCursor(undefined);
    setCommentsHasMore(false);
    setCommentsLoadingMore(false);
    setError("");
    void getRankingToyDetail(id, sort)
      .then((nextDetail) => {
        if (!active) return;
        setDetail(nextDetail);
        setWanted(Boolean(nextDetail.viewerState?.wanted));
        setOwned(Boolean(nextDetail.viewerState?.owned));
        setRatingSelection(nextDetail.viewerState?.rating ?? 10);
        setComments(nextDetail.comments);
        setCommentsCursor(nextDetail.commentsNextCursor);
        setCommentsHasMore(nextDetail.commentsHasMore && Boolean(nextDetail.commentsNextCursor));
        writeRankingToyCache(nextDetail);
      })
      .catch((requestError: unknown) => {
        if (active) setError(formatError(requestError, "商品详情暂时无法加载，请稍后再试"));
      })
      .finally(() => {
        if (!active) return;
        setLoading(false);
        setCommentsLoading(false);
      });
    return () => { active = false; };
  }, [id, sort]);

  function loginForCurrentPage() {
    router.push(`/login?next=${encodeURIComponent(currentLocalPath(pathname, window.location.search))}`);
  }

  function updateCachedDetail(next: RankingToyDetail) {
    setDetail(next);
    writeRankingToyCache(next);
  }

  function toggleWanted() {
    if (!detail) return;
    if (!user) {
      loginForCurrentPage();
      return;
    }
    const next = !wanted;
    const nextDetail = {
      ...detail,
      viewerState: {
        wanted: next,
        owned: Boolean(detail.viewerState?.owned),
        rating: detail.viewerState?.rating,
      },
    } satisfies RankingToyDetail;
    setWanted(next);
    updateCachedDetail(nextDetail);

    // 想冲页首屏只依赖商品数据，先导航，再静默同步写入状态。
    if (next) router.push(`/wishlist?id=${encodeURIComponent(detail.id)}`);
    void setRankingToyWant(detail.id, next).catch((requestError: unknown) => {
      const rollback = {
        ...nextDetail,
        viewerState: { ...nextDetail.viewerState, wanted: !next },
      } satisfies RankingToyDetail;
      setWanted(!next);
      writeRankingToyCache(rollback);
      setError(formatError(requestError, "想冲状态保存失败，请稍后重试"));
    });
  }

  async function toggleOwned() {
    if (!detail) return;
    if (!user) {
      loginForCurrentPage();
      return;
    }
    const next = !owned;
    setOwned(next);
    try {
      await setRankingToyOwned(detail.id, next);
      const nextDetail = {
        ...detail,
        viewerState: {
          wanted: Boolean(detail.viewerState?.wanted),
          owned: next,
          rating: detail.viewerState?.rating,
        },
      } satisfies RankingToyDetail;
      updateCachedDetail(nextDetail);
    } catch (requestError) {
      setOwned(!next);
      setError(formatError(requestError, "购买状态保存失败，请稍后重试"));
    }
  }

  async function loadMoreComments() {
    if (commentsLoadingMore || !commentsHasMore || !commentsCursor) return;
    const cursor = commentsCursor;
    setCommentsLoadingMore(true);
    setError("");
    try {
      const page = await getRankingToyComments(detail?.id || id, sort, cursor);
      setComments((current) => {
        const ids = new Set(current.map((item) => item.id));
        return [...current, ...page.items.filter((item) => !ids.has(item.id))];
      });
      setCommentsCursor(page.nextCursor);
      setCommentsHasMore(page.hasMore && Boolean(page.nextCursor) && page.nextCursor !== cursor);
    } catch (requestError) {
      setError(formatError(requestError, "加载更多评价失败，请稍后重试"));
    } finally {
      setCommentsLoadingMore(false);
    }
  }

  async function submitComment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!detail || !comment.trim() || commentBusy) return;
    if (!user) {
      loginForCurrentPage();
      return;
    }
    setCommentBusy(true);
    setCommentError("");
    try {
      const next = await createRankingToyComment(detail.id, comment.trim());
      setComments((current) => [next, ...current.filter((item) => item.id !== next.id)]);
      setDetail((current) => current ? { ...current, comments: [next, ...current.comments.filter((item) => item.id !== next.id)] } : current);
      setComment("");
    } catch (requestError) {
      setCommentError(formatError(requestError, "评价发送失败，请稍后重试"));
    } finally {
      setCommentBusy(false);
    }
  }

  function toggleCommentLike(item: RankingToyComment) {
    if (!user) {
      loginForCurrentPage();
      return;
    }
    if (likingCommentIds[item.id]) return;
    const nextLiked = !item.viewerState.hasLiked;
    const optimisticCount = Math.max(0, item.likeCount + (nextLiked ? 1 : -1));
    const optimistic = { ...item, likeCount: optimisticCount, viewerState: { hasLiked: nextLiked } };
    setLikingCommentIds((current) => ({ ...current, [item.id]: true }));
    setComments((current) => current.map((commentItem) => commentItem.id === item.id ? optimistic : commentItem));
    void setRankingToyCommentLike(item.id, nextLiked)
      .then((result) => {
        setComments((current) => current.map((commentItem) => commentItem.id === item.id
          ? { ...commentItem, likeCount: result.likeCount, viewerState: { hasLiked: result.active } }
          : commentItem));
      })
      .catch((requestError: unknown) => {
        setComments((current) => current.map((commentItem) => commentItem.id === item.id ? item : commentItem));
        setError(formatError(requestError, "评价点赞失败，请稍后重试"));
      })
      .finally(() => {
        setLikingCommentIds((current) => {
          const nextState = { ...current };
          delete nextState[item.id];
          return nextState;
        });
      });
  }

  function updateCommentAfterThread(comment: RankingToyComment) {
    const rootId = comment.rootId || comment.parentId;
    if (!rootId) return;
    setComments((current) => current.map((item) => item.id === rootId
      ? { ...item, replyCount: item.replyCount + 1 }
      : item));
  }

  async function submitRating(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!detail || ratingBusy) return;
    if (!user) {
      loginForCurrentPage();
      return;
    }
    setRatingBusy(true);
    try {
      const ratedToy = await rateRankingToy(detail.id, ratingSelection);
      const nextDetail = {
        ...detail,
        ...ratedToy,
        releaseYear: detail.releaseYear,
        ratingDistribution: detail.ratingDistribution,
        comments: detail.comments,
        commentsNextCursor: detail.commentsNextCursor,
        commentsHasMore: detail.commentsHasMore,
        commentSort: detail.commentSort,
      } satisfies RankingToyDetail;
      updateCachedDetail(nextDetail);
      setRatingOpen(false);
    } catch (requestError) {
      setError(formatError(requestError, "评分保存失败，请稍后重试"));
    } finally {
      setRatingBusy(false);
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
      <div className="ranking-detail-mobile-header"><button type="button" aria-label="返回" onClick={() => router.push(returnPath)}><Icon name="chevron-left" size={22} /></button><Icon name="box" size={18} /><button type="button" aria-label="分享" onClick={() => void share()}><Icon name="arrow-up-right" size={20} /></button></div>
      <main className="page-frame ranking-detail-frame">
        <button type="button" className="back-link ranking-detail-desktop-back" onClick={() => router.push(returnPath)}><Icon name="chevron-left" size={17} />返回榜单</button>
        {error && <div className="data-note" role="status">{error}</div>}
        <section className="ranking-detail-card">
          <div className="ranking-detail-product">
            <div className="ranking-detail-cover"><MediaImage sources={[detail.coverUrl, detail.heroUrl]} alt={detail.name} loading="eager" /></div>
            <div className="ranking-detail-product-copy"><h1>{detail.name}</h1><p>{detail.merchant}{detail.releaseYear ? ` · ${detail.releaseYear}` : ""}</p><div className="ranking-detail-tags">{detail.tags.slice(0, 3).map((tag) => <span key={tag}>#{tag}</span>)}</div></div>
          </div>
          <p className="ranking-detail-description">{detail.description || "暂无产品介绍"}</p>
          <RatingSummary detail={detail} onRate={() => { setRatingSelection(detail.viewerState?.rating ?? 10); setRatingOpen(true); }} />
          <div className="ranking-detail-actions"><button type="button" className={`ranking-want-button${wanted ? " active" : ""}`} onClick={toggleWanted}><Icon name="heart" size={18} fill={wanted ? "currentColor" : "none"} />{wanted ? "已想冲" : "想冲"}<small>{compactCount(detail.wantCount)} 人想冲</small></button><button type="button" className={`ranking-owned-button${owned ? " active" : ""}`} onClick={() => void toggleOwned()}><Icon name="sparkle" size={17} />{owned ? "已买过" : "买过"}<small>{detail.ratingCount} 人评分</small></button></div>
        </section>
        <section className="ranking-reviews-section">
          <div className="ranking-reviews-heading"><h2>评价 <span>{comments.length}{commentsHasMore ? "+" : ""}</span></h2><div><button type="button" className={sort === "weight" ? "active" : ""} onClick={() => setSort("weight")}>按权重排序</button><button type="button" className={sort === "latest" ? "active" : ""} onClick={() => setSort("latest")}>最新</button></div></div>
          {commentsLoading && !comments.length ? <div className="ranking-comments-skeleton" aria-label="评价加载中"><span /><span /><span /></div> : comments.length ? <div className="ranking-review-list">{comments.map((item) => <RankingReview key={item.id} item={item} likeBusy={Boolean(likingCommentIds[item.id])} onLike={() => toggleCommentLike(item)} onReply={() => setThreadRoot(item)} />)}</div> : <div className="ranking-comments-empty">暂无评价，来发第一条吧</div>}
          {commentsHasMore && <button type="button" className="load-more-button" disabled={commentsLoadingMore} onClick={() => void loadMoreComments}>{commentsLoadingMore ? "加载中…" : "加载更多评价"}</button>}
        </section>
        <form className="ranking-detail-composer" onSubmit={submitComment}><input value={comment} onChange={(event) => setComment(event.target.value)} onFocus={() => { if (!user) loginForCurrentPage(); }} placeholder="来，说点什么吧!" aria-label="发表评价" maxLength={5000} /><button type="submit" aria-label="发送评价" disabled={commentBusy}><Icon name="message" size={18} /></button>{commentError && <div className="form-error">{commentError}</div>}</form>
      </main>
      {ratingOpen && <div className="ranking-rating-dialog-overlay" role="presentation" onMouseDown={() => { if (!ratingBusy) setRatingOpen(false); }}><form className="ranking-rating-dialog" role="dialog" aria-modal="true" aria-labelledby="ranking-rating-dialog-title" onSubmit={(event) => void submitRating(event)} onMouseDown={(event) => event.stopPropagation()}><button type="button" className="ranking-dialog-close" aria-label="关闭评分" onClick={() => setRatingOpen(false)}><Icon name="close" size={18} /></button><h2 id="ranking-rating-dialog-title">给这款玩具评分</h2><output>{ratingSelection} 分</output><RatingHearts rating={ratingSelection} size={21} /><input aria-label="评分，1 到 10 分" type="range" min="1" max="10" step="1" value={ratingSelection} onChange={(event) => setRatingSelection(Number(event.target.value))} /><div className="ranking-rating-dialog-scale"><span>1 分</span><span>10 分</span></div><div className="ranking-rating-dialog-actions"><button type="button" onClick={() => setRatingOpen(false)}>取消</button><button type="submit" className="primary-submit" disabled={ratingBusy}>{ratingBusy ? "保存中…" : "提交评分"}</button></div></form></div>}
      {threadRoot && <RankingCommentThreadSheet toyId={detail.id} rootComment={threadRoot} onClose={() => setThreadRoot(null)} onRequireAuth={loginForCurrentPage} onCommentCreated={updateCommentAfterThread} />}
    </>
  );
}

function RatingSummary({ detail, onRate }: { detail: RankingToyDetail; onRate: () => void }) {
  const buckets = [
    ["5", (detail.ratingDistribution["10"] || 0) + (detail.ratingDistribution["9"] || 0)],
    ["4", (detail.ratingDistribution["8"] || 0) + (detail.ratingDistribution["7"] || 0)],
    ["3", (detail.ratingDistribution["6"] || 0) + (detail.ratingDistribution["5"] || 0)],
    ["2", (detail.ratingDistribution["4"] || 0) + (detail.ratingDistribution["3"] || 0)],
    ["1", (detail.ratingDistribution["2"] || 0) + (detail.ratingDistribution["1"] || 0)],
  ] as const;
  const max = Math.max(...buckets.map(([, value]) => value), 1);
  return <div className="ranking-rating-summary ranking-rating-summary-interactive" role="button" tabIndex={0} aria-label={`点击评分，当前 ${scoreText(detail.score)} 分`} onClick={onRate} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onRate(); } }}><div className="ranking-rating-score"><span>酱友评分</span><strong>{scoreText(detail.score)}</strong><RatingHearts rating={detail.score} size={13} /></div><div className="ranking-rating-bars">{buckets.map(([label, value]) => <div key={label}><span>{label}</span><i><b style={{ width: `${Math.max(2, value / max * 100)}%` }} /></i></div>)}</div></div>;
}

function RatingHearts({ rating, size }: { rating?: number; size: number }) {
  const filled = rating == null ? 5 : Math.max(0, Math.min(5, Math.floor((rating + 1) / 2)));
  return <span className="ranking-rating-hearts" aria-label={rating == null ? undefined : `${rating} 分`}>{Array.from({ length: 5 }, (_, index) => <Icon key={index} name="heart" size={size} fill={index < filled ? "currentColor" : "none"} strokeWidth={1.7} />)}</span>;
}

function RankingReview({ item, likeBusy, onLike, onReply }: { item: RankingToyComment; likeBusy: boolean; onLike: () => void; onReply: () => void }) {
  return <article className="ranking-review"><UserAvatar userId={item.author.id} name={item.author.nickname} url={item.author.avatarUrl} size="small" /><div className="ranking-review-copy"><div className="ranking-review-author"><strong>{item.author.nickname}</strong><span>Lv.{item.author.level || 1}</span><time>{relativeTime(item.createdAt)}</time></div>{item.rating != null && <div className="ranking-review-rating"><RatingHearts rating={item.rating} size={12} /><strong>{item.rating}分</strong></div>}<p>{item.content}</p>{item.media.length > 0 && <div className="ranking-review-media">{item.media.map((media) => <MediaImage key={media.id} asset={media} alt="评价配图" />)}</div>}<div className="ranking-review-actions"><button type="button" className={item.viewerState.hasLiked ? "liked" : ""} disabled={likeBusy} onClick={onLike}><Icon name="heart" size={15} fill={item.viewerState.hasLiked ? "currentColor" : "none"} />{item.likeCount}</button><button type="button" onClick={onReply}>回复{item.replyCount > 0 ? ` ${item.replyCount}` : ""}</button></div></div></article>;
}
