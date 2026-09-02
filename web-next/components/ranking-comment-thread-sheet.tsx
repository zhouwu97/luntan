"use client";

import { useEffect, useState } from "react";
import { Icon } from "./icons";
import { MediaImage } from "./media-image";
import { UserAvatar } from "./user-avatar";
import { useSession } from "./session-provider";
import { formatError, relativeTime } from "../lib/format";
import { createRankingToyComment, getRankingToyCommentReplies, setRankingToyCommentLike } from "../lib/api/forum";
import type { RankingToyComment } from "../types/forum";

export function RankingCommentThreadSheet({
  toyId,
  rootComment,
  onClose,
  onRequireAuth,
  onCommentCreated,
}: {
  toyId: string;
  rootComment: RankingToyComment;
  onClose: () => void;
  onRequireAuth: () => void;
  onCommentCreated: (comment: RankingToyComment) => void;
}) {
  const { user } = useSession();
  const [replies, setReplies] = useState<RankingToyComment[]>([]);
  const [cursor, setCursor] = useState<string>();
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [loadMoreError, setLoadMoreError] = useState("");
  const [replyTarget, setReplyTarget] = useState<RankingToyComment | null>(null);
  const [content, setContent] = useState("");
  const [sending, setSending] = useState(false);
  const [likeBusy, setLikeBusy] = useState<Record<string, boolean>>({});

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", onKeyDown);
    void loadFirstPage();
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", onKeyDown);
    };
    // 弹层每次只对应一条根评价，打开时加载一次。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function loadFirstPage() {
    setLoading(true);
    setLoadError("");
    setReplies([]);
    setCursor(undefined);
    setHasMore(true);
    try {
      const page = await getRankingToyCommentReplies(rootComment.id);
      setReplies(page.items);
      setCursor(page.nextCursor);
      setHasMore(page.hasMore && Boolean(page.nextCursor));
    } catch (requestError) {
      setLoadError(formatError(requestError, "回复加载失败，请重试"));
    } finally {
      setLoading(false);
    }
  }

  async function loadMoreReplies() {
    if (loading || loadingMore || !hasMore || !cursor) return;
    const currentCursor = cursor;
    setLoadingMore(true);
    setLoadMoreError("");
    try {
      const page = await getRankingToyCommentReplies(rootComment.id, currentCursor);
      setReplies((current) => {
        const ids = new Set(current.map((item) => item.id));
        return [...current, ...page.items.filter((item) => !ids.has(item.id))];
      });
      setCursor(page.nextCursor);
      setHasMore(page.hasMore && Boolean(page.nextCursor) && page.nextCursor !== currentCursor);
    } catch (requestError) {
      setLoadMoreError(formatError(requestError, "加载更多失败，点击重试"));
    } finally {
      setLoadingMore(false);
    }
  }

  async function sendReply() {
    const value = content.trim();
    if (!value || sending) return;
    if (!user) {
      onRequireAuth();
      return;
    }
    const target = replyTarget || rootComment;
    setSending(true);
    setLoadMoreError("");
    try {
      const created = await createRankingToyComment(toyId, value, target.id, target.author.id);
      setReplies((current) => current.some((item) => item.id === created.id) ? current : [...current, created]);
      setContent("");
      setReplyTarget(null);
      onCommentCreated(created);
    } catch (requestError) {
      setLoadMoreError(formatError(requestError, "回复失败，请重试"));
    } finally {
      setSending(false);
    }
  }

  function toggleLike(reply: RankingToyComment) {
    if (!user) {
      onRequireAuth();
      return;
    }
    if (likeBusy[reply.id]) return;
    const nextLiked = !reply.viewerState.hasLiked;
    const optimistic = { ...reply, likeCount: Math.max(0, reply.likeCount + (nextLiked ? 1 : -1)), viewerState: { hasLiked: nextLiked } };
    setLikeBusy((current) => ({ ...current, [reply.id]: true }));
    setReplies((current) => current.map((item) => item.id === reply.id ? optimistic : item));
    void setRankingToyCommentLike(reply.id, nextLiked)
      .then((result) => setReplies((current) => current.map((item) => item.id === reply.id
        ? { ...item, likeCount: result.likeCount, viewerState: { hasLiked: result.active } }
        : item)))
      .catch((requestError: unknown) => {
        setReplies((current) => current.map((item) => item.id === reply.id ? reply : item));
        setLoadMoreError(formatError(requestError, "点赞失败，请重试"));
      })
      .finally(() => setLikeBusy((current) => {
        const next = { ...current };
        delete next[reply.id];
        return next;
      }));
  }

  const replyCount = Math.max(rootComment.replyCount, replies.length);
  return <div className="ranking-thread-overlay" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose(); }}><section className="ranking-thread-sheet" role="dialog" aria-modal="true" aria-labelledby="ranking-thread-title"><span className="ranking-thread-grabber" /><header><h2 id="ranking-thread-title">{replyCount} 条回复</h2><button type="button" aria-label="关闭楼中楼" onClick={onClose}><Icon name="close" size={20} /></button></header><div className="ranking-thread-scroll" onScroll={(event) => { const target = event.currentTarget; if (target.scrollHeight - target.scrollTop - target.clientHeight < 180) void loadMoreReplies(); }}><div className="ranking-thread-root"><UserAvatar userId={rootComment.author.id} name={rootComment.author.nickname} url={rootComment.author.avatarUrl} size="small" /><div><div className="ranking-thread-author"><strong>{rootComment.author.nickname}</strong><span>Lv.{rootComment.author.level || 1}</span><ThreadRating rating={rootComment.rating} /></div><p>{rootComment.content}</p>{rootComment.media.length > 0 && <ThreadMedia media={rootComment.media} />}</div></div><div className="ranking-thread-divider" /><h3>二级回复</h3>{loading && !replies.length ? <div className="ranking-thread-loading"><span /><span /><span /></div> : loadError && !replies.length ? <button type="button" className="ranking-thread-retry" onClick={() => void loadFirstPage()}>{loadError}</button> : !replies.length ? <div className="ranking-thread-empty">暂无二级回复，来发第一条吧</div> : <div className="ranking-thread-replies">{replies.map((reply) => <ThreadReply key={reply.id} reply={reply} replyTo={replyToName(reply, rootComment, replies)} busy={Boolean(likeBusy[reply.id])} onReply={() => setReplyTarget(reply)} onLike={() => toggleLike(reply)} />)}</div>}{loadingMore && <div className="ranking-thread-loading-more">加载中…</div>}{loadMoreError && !loadingMore && <button type="button" className="ranking-thread-retry ranking-thread-more-retry" onClick={() => void loadMoreReplies()}>{loadMoreError}</button>}</div><div className="ranking-thread-composer"><input value={content} onChange={(event) => setContent(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && !event.nativeEvent.isComposing) { event.preventDefault(); void sendReply(); } }} disabled={sending} placeholder={replyTarget ? `回复 @${replyTarget.author.nickname}…` : "友善地回复一句…"} maxLength={5000} aria-label="回复内容" /><button type="button" onClick={() => void sendReply()} disabled={sending || !content.trim()}>{sending ? "发送中…" : "发送"}</button></div></section></div>;
}

function replyToName(reply: RankingToyComment, root: RankingToyComment, replies: RankingToyComment[]) {
  if (!reply.replyToUserId) return "";
  if (reply.replyToUserId === root.author.id) return root.author.nickname;
  const target = replies.find((item) => item.author.id === reply.replyToUserId);
  return target?.author.nickname || reply.replyToUser?.nickname || "用户";
}

function ThreadReply({ reply, replyTo, busy, onReply, onLike }: { reply: RankingToyComment; replyTo: string; busy: boolean; onReply: () => void; onLike: () => void }) {
  return <article className="ranking-thread-reply"><UserAvatar userId={reply.author.id} name={reply.author.nickname} url={reply.author.avatarUrl} size="small" /><div className="ranking-thread-reply-copy"><div className="ranking-thread-author"><strong>{reply.author.nickname}</strong><span>Lv.{reply.author.level || 1}</span><time>{relativeTime(reply.createdAt)}</time></div>{replyTo && <div className="ranking-thread-reply-to">回复 @{replyTo}</div>}<p>{reply.content}</p>{reply.media.length > 0 && <ThreadMedia media={reply.media} />}<div className="ranking-thread-reply-actions"><button type="button" onClick={onReply}>回复</button><button type="button" className={reply.viewerState.hasLiked ? "liked" : ""} disabled={busy} onClick={onLike}><Icon name="heart" size={14} fill={reply.viewerState.hasLiked ? "currentColor" : "none"} />{reply.likeCount}</button></div></div></article>;
}

function ThreadRating({ rating }: { rating?: number }) {
  if (rating == null) return null;
  const filled = Math.max(0, Math.min(5, Math.floor((rating + 1) / 2)));
  return <span className="ranking-thread-rating">{Array.from({ length: 5 }, (_, index) => <Icon key={index} name="heart" size={11} fill={index < filled ? "currentColor" : "none"} />)}<b>{rating}分</b></span>;
}

function ThreadMedia({ media }: { media: RankingToyComment["media"] }) {
  return <div className="ranking-thread-media">{media.map((asset) => <MediaImage key={asset.id} asset={asset} alt="回复配图" />)}</div>;
}
