"use client";

import Link from "next/link";
import { FormEvent, MouseEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "./site-header";
import { Icon } from "./icons";
import { MediaImage } from "./media-image";
import { UserAvatar } from "./user-avatar";
import { useSession } from "./session-provider";
import { createComment, createReply, getCommentReplies, getComments, getFeed, getPost, recordHistory, setCommentLike, setPostBookmark, setPostLike } from "../lib/api/forum";
import { compactCount, formatError, relativeTime } from "../lib/format";
import type { Comment, Post, SessionUser } from "../types/forum";

export function PostDetailShell({ id }: { id: string }) {
  const router = useRouter();
  const { user } = useSession();
  const [post, setPost] = useState<Post | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [related, setRelated] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let mounted = true;
    setLoading(true);
    setError("");
    void Promise.all([getPost(id), getComments(id), getFeed({ sort: "hot", limit: 4 })])
      .then(([nextPost, nextComments, nextRelated]) => {
        if (!mounted) return;
        setPost(nextPost);
        setComments(nextComments);
        setRelated(nextRelated.items.filter((item) => item.id !== id).slice(0, 4));
      })
      .catch((requestError: unknown) => {
        if (!mounted) return;
        setPost(null);
        setComments([]);
        setRelated([]);
        setError(formatError(requestError, "帖子暂时无法加载，请稍后再试"));
      })
      .finally(() => {
        if (mounted) setLoading(false);
      });
    return () => {
      mounted = false;
    };
  }, [id]);

  useEffect(() => {
    if (user && post) void recordHistory(post.id).catch(() => undefined);
  }, [post, user]);

  if (loading && !post) {
    return <><SiteHeader /><main className="page-frame"><div className="detail-skeleton"><div /><div /><div /></div></main></>;
  }

  if (!post) {
    return <><SiteHeader /><main className="page-frame"><div className="empty-state"><h1>帖子不存在</h1><p>这条内容可能已被删除。</p><Link href="/" className="primary-link">返回首页</Link></div></main></>;
  }

  return (
    <>
      <SiteHeader className="post-detail-site-header" />
      <div className="post-mobile-header"><Link href="/" aria-label="返回首页"><Icon name="chevron-left" size={22} /></Link><strong>{post.community.name}</strong><button type="button" aria-label="更多操作"><Icon name="more" size={19} /></button></div>
      <main className="page-frame">
        <div className="detail-grid">
          <section className="detail-main">
            <Link href="/" className="back-link detail-back"><Icon name="chevron-left" size={17} />返回首页</Link>
            {error && <div className="data-note">网络连接暂时不可用，已展示最近缓存的公开内容</div>}
            <PostArticle post={post} user={user} onRequireAuth={() => router.push("/login")} />
            <CommentsSection post={post} comments={comments} setComments={setComments} user={user} onRequireAuth={() => router.push("/login")} />
          </section>
          <DetailAside post={post} related={related} />
        </div>
      </main>
    </>
  );
}

function PostArticle({ post, user, onRequireAuth }: { post: Post; user: SessionUser | null; onRequireAuth: () => void }) {
  const [liked, setLiked] = useState(post.viewerState.hasLiked);
  const [bookmarked, setBookmarked] = useState(post.viewerState.hasBookmarked);
  const [likeCount, setLikeCount] = useState(post.likeCount);
  const [bookmarkCount, setBookmarkCount] = useState(post.bookmarkCount);

  async function toggleLike() {
    if (!user) return onRequireAuth();
    const next = !liked;
    setLiked(next);
    setLikeCount((value) => value + (next ? 1 : -1));
    try {
      await setPostLike(post.id, next);
    } catch {
      setLiked(!next);
      setLikeCount((value) => value + (next ? -1 : 1));
    }
  }

  async function toggleBookmark() {
    if (!user) return onRequireAuth();
    const next = !bookmarked;
    setBookmarked(next);
    setBookmarkCount((value) => Math.max(0, value + (next ? 1 : -1)));
    try {
      await setPostBookmark(post.id, next);
    } catch {
      setBookmarked(!next);
      setBookmarkCount((value) => Math.max(0, value + (next ? -1 : 1)));
    }
  }

  return (
    <article className="detail-article">
      <div className="detail-community"><span className="community-icon lilac"><Icon name="trophy" size={18} /></span><span>{post.community.name}</span><button type="button" className="more-button" aria-label="更多操作"><Icon name="more" size={18} /></button></div>
      <h1>{post.title}</h1>
      <div className="detail-author-row"><UserAvatar userId={post.author.id} name={post.author.nickname} url={post.author.avatarUrl} /><div><strong>{post.author.nickname}</strong><div className="post-meta">{post.community.name} <span>·</span> {relativeTime(post.createdAt)}</div></div><span className="level-label">Lv.{post.author.level || 1}</span></div>
      <p className="detail-content">{post.content}</p>
      {post.media.length > 0 && <div className="detail-gallery">{post.media.map((media) => <MediaImage key={media.id} asset={media} alt={media.altText || "帖子图片"} className="detail-media-image" />)}</div>}
      <div className="detail-engagement">
        <div className="detail-engagement-left">
          <button type="button" className={`engagement-button${liked ? " selected-like" : ""}`} onClick={toggleLike}><Icon name="heart" size={19} />{compactCount(likeCount)} 赞</button>
          <span className="engagement-button"><Icon name="message" size={19} />{compactCount(post.commentCount)} 条回复</span>
          <button type="button" className={`engagement-button${bookmarked ? " selected-bookmark" : ""}`} onClick={toggleBookmark}><Icon name="bookmark" size={19} />{bookmarked ? "已收藏" : "收藏"}{bookmarkCount > 0 && ` ${compactCount(bookmarkCount)}`}</button>
        </div>
        <span className="detail-views"><Icon name="eye" size={18} />{compactCount(post.viewCount)} 浏览</span>
      </div>
    </article>
  );
}

function CommentsSection({ post, comments, setComments, user, onRequireAuth }: { post: Post; comments: Comment[]; setComments: (items: Comment[]) => void; user: SessionUser | null; onRequireAuth: () => void }) {
  const [content, setContent] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [replyTarget, setReplyTarget] = useState<Comment | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) return onRequireAuth();
    const value = content.trim();
    if (!value || busy) return;
    setBusy(true);
    setMessage("");
    try {
      const next = await createComment(post.id, value);
      setComments([...comments, next]);
      setContent("");
    } catch (requestError) {
      setMessage(formatError(requestError, "回复发送失败，请稍后重试"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="comments-section" id="comments">
      <div className="comments-heading"><h2>全部回复 <span>（{post.commentCount}）</span></h2><button type="button" className="sort-comments">按时间 <Icon name="chevron-right" size={15} /></button></div>
      <form className="comment-composer" onSubmit={submit}>
        <UserAvatar userId={user?.id} name={user?.nickname || "我"} url={user?.avatarUrl} className="avatar-comment" />
        <div className="composer-box"><textarea value={content} onChange={(event) => setContent(event.target.value)} placeholder={user ? "说点什么吧…" : "登录后参与回复"} rows={2} onFocus={() => { if (!user) onRequireAuth(); }} /><div className="composer-footer"><div className="composer-tools"><button type="button" aria-label="添加图片"><Icon name="image" size={19} /></button><button type="button" aria-label="添加表情"><Icon name="sparkle" size={19} /></button><button type="button" aria-label="提及用户"><Icon name="at" size={19} /></button></div><button type="submit" className="reply-submit" disabled={busy}>{busy ? "发送中…" : "发布回复"}</button></div></div>
      </form>
      {message && <div className="form-error">{message}</div>}
      <div className="comment-list">{comments.length ? comments.map((comment) => <CommentRow key={comment.id} comment={comment} user={user} onRequireAuth={onRequireAuth} onReply={() => setReplyTarget(comment)} />) : <div className="comment-empty">还没有回复，来做第一个分享的人吧。</div>}</div>
      {replyTarget && <CommentReplyModal root={replyTarget} user={user} onRequireAuth={onRequireAuth} onClose={() => setReplyTarget(null)} />}
    </section>
  );
}

function CommentRow({ comment, user, onRequireAuth, onReply }: { comment: Comment; user: SessionUser | null; onRequireAuth: () => void; onReply: () => void }) {
  const [liked, setLiked] = useState(comment.viewerState.hasLiked);
  const [count, setCount] = useState(comment.likeCount);

  async function like(event: MouseEvent<HTMLButtonElement>) {
    event.preventDefault();
    if (!user) return onRequireAuth();
    const next = !liked;
    setLiked(next);
    setCount((value) => value + (next ? 1 : -1));
    try {
      await setCommentLike(comment.id, next);
    } catch {
      setLiked(!next);
      setCount((value) => value + (next ? -1 : 1));
    }
  }

  return <article className={`comment-row${liked ? " liked" : ""}`}><UserAvatar userId={comment.author.id} name={comment.author.nickname} url={comment.author.avatarUrl} className="avatar-comment" /><div className="comment-body"><div className="comment-author-line"><strong>{comment.author.nickname}</strong><span className="level-label">Lv.{comment.author.level || 1}</span><span className="comment-time">{relativeTime(comment.createdAt)}</span><span className="comment-floor">#{comment.floor || ""}</span></div><p>{comment.content}</p><div className="comment-actions"><button type="button" onClick={like}><Icon name="heart" size={16} />{count}</button><button type="button" onClick={onReply}><Icon name="message" size={16} />回复</button></div>{comment.replyPreview?.map((reply) => <div className="reply-preview" key={reply.id}><strong>{reply.author.nickname}</strong><span>{reply.content}</span></div>)}</div><button type="button" className="comment-more" aria-label="评论更多操作"><Icon name="more" size={18} /></button></article>;
}

function CommentReplyModal({ root, user, onRequireAuth, onClose }: { root: Comment; user: SessionUser | null; onRequireAuth: () => void; onClose: () => void }) {
  const [replies, setReplies] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);
  const [content, setContent] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    let active = true;
    void getCommentReplies(root.id).then((page) => { if (active) setReplies(page.items); }).catch(() => { if (active) setMessage("回复加载失败，请重试"); }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [root.id]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) return onRequireAuth();
    if (!content.trim() || busy) return;
    setBusy(true);
    try {
      const next = await createReply(root.id, content.trim());
      setReplies((current) => [...current, next]);
      setContent("");
    } catch (requestError) {
      setMessage(formatError(requestError, "回复发送失败，请稍后重试"));
    } finally {
      setBusy(false);
    }
  }

  return <div className="comment-reply-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="comment-reply-modal" role="dialog" aria-modal="true" aria-label="评论回复"><div className="comment-reply-grabber" /><header><h2>{replies.length || root.replyCount} 条回复</h2><button type="button" aria-label="关闭回复" onClick={onClose}><Icon name="close" size={19} /></button></header><div className="comment-reply-scroll"><div className="comment-reply-root"><UserAvatar userId={root.author.id} name={root.author.nickname} url={root.author.avatarUrl} className="avatar-comment" /><div><strong>{root.author.nickname}</strong><p>{root.content}</p></div></div>{loading ? <div className="comment-empty">正在加载回复…</div> : replies.map((reply) => <div className="comment-reply-item" key={reply.id}><UserAvatar userId={reply.author.id} name={reply.author.nickname} url={reply.author.avatarUrl} className="avatar-comment" /><div><div><strong>{reply.author.nickname}</strong><span className="comment-time">{relativeTime(reply.createdAt)}</span></div><p>{reply.content}</p><div className="comment-actions"><button type="button">回复</button><button type="button"><Icon name="heart" size={15} />{reply.likeCount}</button></div></div></div>)}</div><form className="comment-reply-composer" onSubmit={submit}><input value={content} onChange={(event) => setContent(event.target.value)} placeholder="友善地回复一句…" /><button type="submit" disabled={busy}>{busy ? "发送中" : "发送"}</button></form>{message && <div className="form-error">{message}</div>}</section></div>;
}

function DetailAside({ post, related }: { post: Post; related: Post[] }) {
  return <aside className="detail-aside"><section className="aside-panel author-panel"><h2>作者信息</h2><div className="aside-author"><UserAvatar userId={post.author.id} name={post.author.nickname} url={post.author.avatarUrl} size="large" /><div><strong>{post.author.nickname}</strong><span className="level-label">Lv.{post.author.level || 1}</span><p>热爱拆箱和分享真实使用体验。</p></div></div><button type="button" className="outline-button">+ 关注</button></section><section className="aside-panel community-panel"><h2>来自社区</h2><div className="aside-community"><span className="community-icon lilac"><Icon name="trophy" size={19} /></span><div><strong>{post.community.name}</strong><p>{post.community.description || "和同好聊聊最近的新发现"}</p></div><Icon name="chevron-right" size={18} /></div><button type="button" className="outline-button">进入社区</button></section><section className="aside-panel related-panel"><div className="discovery-heading"><h2>相关帖子</h2><button type="button">更多 <Icon name="chevron-right" size={15} /></button></div>{related.length ? related.map((item) => <Link href={`/post/${encodeURIComponent(item.id)}`} className="related-post" key={item.id}>{item.media[0] ? <MediaImage asset={item.media[0]} alt="" className="related-media-image" /> : <span className="related-placeholder"><Icon name="box" size={19} /></span>}<span><strong>{item.title}</strong><small>{item.author.nickname}</small></span></Link>) : <p className="empty-rail">暂无相关帖子</p>}</section></aside>;
}
