"use client";

import Link from "next/link";
import { FormEvent, MouseEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "./site-header";
import { AppDownloadBanner } from "./app-download-banner";
import { Icon } from "./icons";
import { MediaImage } from "./media-image";
import { UserAvatar } from "./user-avatar";
import { useSession } from "./session-provider";
import { useToast } from "./toast-context";
import {
  createComment,
  createReply,
  getCommentReplies,
  getComments,
  getFeed,
  getPost,
  recordHistory,
  setCommentLike,
  setPostBookmark,
  setPostLike,
} from "../lib/api/forum";
import { compactCount, formatError, relativeTime } from "../lib/format";
import type { Comment, Post, SessionUser } from "../types/forum";

export function PostDetailShell({ id }: { id: string }) {
  const router = useRouter();
  const { user } = useSession();
  const { showToast } = useToast();
  const [post, setPost] = useState<Post | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [related, setRelated] = useState<Post[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [mobileComposerOpen, setMobileComposerOpen] = useState(false);
  const [mobileComposerText, setMobileComposerText] = useState("");
  const [sendingComment, setSendingComment] = useState(false);

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

  async function handleMobileSubmitComment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) {
      router.push(`/login?next=${encodeURIComponent(`/post/${id}`)}`);
      return;
    }
    if (!mobileComposerText.trim() || sendingComment) return;
    setSendingComment(true);
    try {
      const newComment = await createComment(id, mobileComposerText.trim());
      setComments((curr) => [...curr, newComment]);
      setMobileComposerText("");
      setMobileComposerOpen(false);
      showToast("回复发布成功！");
    } catch (reqErr) {
      showToast(formatError(reqErr, "回复失败，请重试"));
    } finally {
      setSendingComment(false);
    }
  }

  if (loading && !post) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame">
          <div className="detail-skeleton">
            <div />
            <div />
            <div />
          </div>
        </main>
      </>
    );
  }

  if (!post) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame">
          <div className="empty-state">
            <h1>帖子不存在</h1>
            <p>这条内容可能已被删除。</p>
            <Link href="/" className="primary-link">
              返回首页
            </Link>
          </div>
        </main>
      </>
    );
  }

  return (
    <>
      {/* 桌面端专用顶部导航栏 */}
      <SiteHeader className="post-detail-site-header" />

      {/* 移动端原型顶部 Header */}
      <header className="detail-head mobile-only">
        <button
          type="button"
          className="icon-btn"
          aria-label="返回首页"
          onClick={() => router.push("/")}
        >
          <Icon name="chevron-left" size={22} />
        </button>
        <span className="detail-community-name">{post.community.name}</span>
        <button
          type="button"
          className="icon-btn"
          aria-label="更多操作"
          onClick={() => showToast("已复制帖子链接")}
        >
          <Icon name="more" size={18} />
        </button>
      </header>

      <main className="page-frame post-detail-page-frame">
        <div className="detail-grid">
          <section className="detail-main">
            <Link href="/" className="back-link detail-back desktop-only">
              <Icon name="chevron-left" size={17} />
              返回首页
            </Link>

            {error && <div className="data-note">{error}</div>}

            <PostArticle post={post} user={user} onRequireAuth={() => router.push("/login")} />

            <CommentsSection
              post={post}
              comments={comments}
              setComments={setComments}
              user={user}
              onRequireAuth={() => router.push("/login")}
            />
          </section>

          {/* 桌面端侧边作者与相关推荐 */}
          <DetailAside post={post} related={related} />
        </div>
      </main>

      {/* 移动端底部固定快速回复输入条 */}
      <div className="composer mobile-only">
        <div className="composer-trigger" onClick={() => setMobileComposerOpen(true)}>
          <input
            type="text"
            readOnly
            placeholder="说点什么，参与热烈讨论..."
            value={mobileComposerText}
          />
        </div>
        <div className="composer-side">
          <span className="comp-stat">
            <Icon name="message" size={18} />
            {compactCount(comments.length)}
          </span>
          <button
            type="button"
            className={`comp-stat stat${post.viewerState.hasLiked ? " selected" : ""}`}
            onClick={async () => {
              if (!user) {
                router.push("/login");
                return;
              }
              const next = !post.viewerState.hasLiked;
              setPost((p) =>
                p
                  ? {
                      ...p,
                      likeCount: Math.max(0, p.likeCount + (next ? 1 : -1)),
                      viewerState: { ...p.viewerState, hasLiked: next },
                    }
                  : p
              );
              try {
                await setPostLike(post.id, next);
              } catch {
                // 回滚
              }
            }}
          >
            <Icon name="heart" size={18} />
            {compactCount(post.likeCount)}
          </button>
        </div>
      </div>

      {/* 移动端评论输入弹层 */}
      {mobileComposerOpen && (
        <div
          className="comment-reply-overlay mobile-only"
          onClick={() => setMobileComposerOpen(false)}
        >
          <div
            className="comment-reply-modal"
            style={{ padding: 16 }}
            onClick={(e) => e.stopPropagation()}
          >
            <form onSubmit={handleMobileSubmitComment}>
              <textarea
                autoFocus
                rows={3}
                style={{
                  width: "100%",
                  borderRadius: 12,
                  border: "1px solid #dce8f3",
                  padding: 10,
                  fontSize: 14,
                  resize: "none",
                }}
                placeholder="友善地写下你的评价或想法…"
                value={mobileComposerText}
                onChange={(e) => setMobileComposerText(e.target.value)}
              />
              <div
                style={{
                  display: "flex",
                  justifyContent: "flex-end",
                  gap: 10,
                  marginTop: 10,
                }}
              >
                <button
                  type="button"
                  className="outline-button"
                  onClick={() => setMobileComposerOpen(false)}
                >
                  取消
                </button>
                <button
                  type="submit"
                  className="primary-button"
                  disabled={!mobileComposerText.trim() || sendingComment}
                >
                  {sendingComment ? "发送中…" : "发送"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* 移动端保留的 App 下载浮窗 */}
      <AppDownloadBanner />
    </>
  );
}

function PostArticle({
  post,
  user,
  onRequireAuth,
}: {
  post: Post;
  user: SessionUser | null;
  onRequireAuth: () => void;
}) {
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
    setBookmarkCount((value) => value + (next ? 1 : -1));
    try {
      await setPostBookmark(post.id, next);
    } catch {
      setBookmarked(!next);
      setBookmarkCount((value) => value + (next ? -1 : 1));
    }
  }

  return (
    <article className="detail-article">
      <header className="detail-author">
        <UserAvatar
          userId={post.author.id}
          name={post.author.nickname}
          url={post.author.avatarUrl}
          className="post-avatar"
        />
        <div className="post-author">
          <div className="author-line">
            <span className="author-name">{post.author.nickname}</span>
            <span className="lv">Lv.{post.author.level || 1}</span>
          </div>
          <div className="meta">
            {post.community.name} · {relativeTime(post.createdAt)}
          </div>
        </div>
      </header>

      <h1 className="detail-title">{post.title}</h1>

      <div className="detail-body">
        {post.content.split("\n\n").map((paragraph, index) => (
          <p key={index}>{paragraph}</p>
        ))}
      </div>

      {post.media.length > 0 && (
        <div className="detail-gallery">
          {post.media.map((asset, index) => (
            <MediaImage key={index} asset={asset} alt={`${post.title} 图片 ${index + 1}`} />
          ))}
        </div>
      )}

      <div className="detail-stats">
        <span>
          <Icon name="message" size={15} />
          {compactCount(post.commentCount)} 评论
        </span>
        <button
          type="button"
          className={`stat${liked ? " selected" : ""}`}
          onClick={toggleLike}
          style={{ background: "none", border: "none", cursor: "pointer" }}
        >
          <Icon name="heart" size={15} />
          {compactCount(likeCount)} 点赞
        </button>
        <button
          type="button"
          className={`stat${bookmarked ? " selected" : ""}`}
          onClick={toggleBookmark}
          style={{ background: "none", border: "none", cursor: "pointer" }}
        >
          <Icon name="bookmark" size={15} />
          {compactCount(bookmarkCount)} 收藏
        </button>
        <span>
          <Icon name="eye" size={15} />
          {compactCount(post.viewCount)} 浏览
        </span>
      </div>
    </article>
  );
}

function CommentsSection({
  post,
  comments,
  setComments,
  user,
  onRequireAuth,
}: {
  post: Post;
  comments: Comment[];
  setComments: React.Dispatch<React.SetStateAction<Comment[]>>;
  user: SessionUser | null;
  onRequireAuth: () => void;
}) {
  const [content, setContent] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [landlordOnly, setLandlordOnly] = useState(false);
  const [sortOrder, setSortOrder] = useState<"hot" | "asc" | "desc">("hot");
  const [replyTarget, setReplyTarget] = useState<Comment | null>(null);

  const displayComments = useMemo(() => {
    let result = [...comments];
    if (landlordOnly) {
      result = result.filter((c) => c.author.id === post.author.id);
    }
    if (sortOrder === "hot") {
      result.sort((a, b) => b.likeCount - a.likeCount);
    } else if (sortOrder === "desc") {
      result.reverse();
    }
    return result;
  }, [comments, landlordOnly, post.author.id, sortOrder]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) return onRequireAuth();
    if (!content.trim() || busy) return;
    setBusy(true);
    setMessage("");
    try {
      const next = await createComment(post.id, content.trim());
      setComments((current) => [...current, next]);
      setContent("");
    } catch (requestError) {
      setMessage(formatError(requestError, "评论发送失败，请稍后重试"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="comments-wrap" aria-label="帖子评论区">
      <div className="comments-head">
        <h2 className="comm-title">评论 ({comments.length})</h2>
        <span className="comm-sub">全部回复</span>
      </div>

      {/* 移动端和桌面端通用的排序与只看楼主筛选条 */}
      <div className="comment-tools">
        <div className="chips">
          <button
            type="button"
            className={`chip${sortOrder === "hot" ? " active" : ""}`}
            onClick={() => setSortOrder("hot")}
          >
            热门
          </button>
          <button
            type="button"
            className={`chip${sortOrder === "asc" ? " active" : ""}`}
            onClick={() => setSortOrder("asc")}
          >
            顺序
          </button>
          <button
            type="button"
            className={`chip${sortOrder === "desc" ? " active" : ""}`}
            onClick={() => setSortOrder("desc")}
          >
            倒序
          </button>
        </div>
        <button
          type="button"
          className={`landlord${landlordOnly ? " active" : ""}`}
          onClick={() => setLandlordOnly((v) => !v)}
        >
          只看楼主
        </button>
      </div>

      {/* 桌面端内嵌输入框 */}
      <form className="comment-composer desktop-only" onSubmit={submit}>
        <UserAvatar
          userId={user?.id}
          name={user?.nickname || "客"}
          url={user?.avatarUrl}
          className="avatar-comment"
        />
        <div className="composer-box">
          <textarea
            value={content}
            onChange={(event) => setContent(event.target.value)}
            placeholder={user ? "说点什么吧…" : "登录后参与回复"}
            rows={2}
            onFocus={() => {
              if (!user) onRequireAuth();
            }}
          />
          <div className="composer-footer">
            <button type="submit" className="reply-submit" disabled={busy}>
              {busy ? "发送中…" : "发布回复"}
            </button>
          </div>
        </div>
      </form>

      {message && <div className="form-error">{message}</div>}

      <div className="comment-list">
        {displayComments.length ? (
          displayComments.map((comment: Comment) => (
            <CommentRow
              key={comment.id}
              comment={comment}
              user={user}
              onRequireAuth={onRequireAuth}
              onReply={() => setReplyTarget(comment)}
            />
          ))
        ) : (
          <div className="empty-state" style={{ padding: "30px 0" }}>
            <Icon name="message" size={24} />
            <p>{landlordOnly ? "楼主还没有发表评论" : "还没有回复，来做第一个分享的人吧！"}</p>
          </div>
        )}
      </div>

      {replyTarget && (
        <CommentReplyModal
          root={replyTarget}
          user={user}
          onRequireAuth={onRequireAuth}
          onClose={() => setReplyTarget(null)}
        />
      )}
    </section>
  );
}

function CommentRow({
  comment,
  user,
  onRequireAuth,
  onReply,
}: {
  comment: Comment;
  user: SessionUser | null;
  onRequireAuth: () => void;
  onReply: () => void;
}) {
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

  return (
    <article className="comment-card">
      <UserAvatar
        userId={comment.author.id}
        name={comment.author.nickname}
        url={comment.author.avatarUrl}
        className="comm-avatar"
      />
      <div className="comm-main">
        <div className="comm-head">
          <span className="comm-name">{comment.author.nickname}</span>
          <span className="comm-lv">Lv.{comment.author.level || 1}</span>
          <span className="comm-floor">#{comment.floor || "1"}</span>
        </div>
        <div className="comm-time">{relativeTime(comment.createdAt)}</div>
        <p className="comm-text">{comment.content}</p>

        {comment.replyPreview && comment.replyPreview.length > 0 && (
          <div className="nested" onClick={onReply}>
            <span className="nested-name">{comment.replyPreview[0].author.nickname}: </span>
            <span>{comment.replyPreview[0].content}</span>
            {comment.replyCount > 1 && (
              <div className="more-nested">查看全部 {comment.replyCount} 条回复 &gt;</div>
            )}
          </div>
        )}

        <div className="comm-actions">
          <button
            type="button"
            className={`comm-act${liked ? " selected" : ""}`}
            onClick={like}
          >
            <Icon name="heart" size={14} />
            <span>{count}</span>
          </button>
          <button type="button" className="comm-act" onClick={onReply}>
            <Icon name="message" size={14} />
            <span>回复</span>
          </button>
        </div>
      </div>
    </article>
  );
}

function CommentReplyModal({
  root,
  user,
  onRequireAuth,
  onClose,
}: {
  root: Comment;
  user: SessionUser | null;
  onRequireAuth: () => void;
  onClose: () => void;
}) {
  const [replies, setReplies] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);
  const [content, setContent] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    let active = true;
    void getCommentReplies(root.id)
      .then((page) => {
        if (active) setReplies(page.items);
      })
      .catch(() => {
        if (active) setMessage("回复加载失败，请重试");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
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

  return (
    <div
      className="comment-reply-overlay"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <section
        className="comment-reply-modal"
        role="dialog"
        aria-modal="true"
        aria-label="评论回复"
      >
        <div className="comment-reply-grabber" />
        <header>
          <h2>{replies.length || root.replyCount} 条回复</h2>
          <button type="button" aria-label="关闭回复" onClick={onClose}>
            <Icon name="close" size={19} />
          </button>
        </header>
        <div className="comment-reply-scroll">
          <div className="comment-reply-root">
            <UserAvatar
              userId={root.author.id}
              name={root.author.nickname}
              url={root.author.avatarUrl}
              className="avatar-comment"
            />
            <div>
              <strong>{root.author.nickname}</strong>
              <p>{root.content}</p>
            </div>
          </div>
          {loading ? (
            <div className="comment-empty">正在加载回复…</div>
          ) : (
            replies.map((reply) => (
              <div className="comment-reply-item" key={reply.id}>
                <UserAvatar
                  userId={reply.author.id}
                  name={reply.author.nickname}
                  url={reply.author.avatarUrl}
                  className="avatar-comment"
                />
                <div>
                  <div>
                    <strong>{reply.author.nickname}</strong>
                    <span className="comment-time">{relativeTime(reply.createdAt)}</span>
                  </div>
                  <p>{reply.content}</p>
                </div>
              </div>
            ))
          )}
        </div>
        <form className="comment-reply-composer" onSubmit={submit}>
          <input
            value={content}
            onChange={(event) => setContent(event.target.value)}
            placeholder="友善地回复一句…"
          />
          <button type="submit" disabled={busy}>
            {busy ? "发送中" : "发送"}
          </button>
        </form>
        {message && <div className="form-error">{message}</div>}
      </section>
    </div>
  );
}

function DetailAside({ post, related }: { post: Post; related: Post[] }) {
  return (
    <aside className="detail-aside desktop-only">
      <section className="aside-panel author-panel">
        <h2>作者信息</h2>
        <div className="aside-author">
          <UserAvatar
            userId={post.author.id}
            name={post.author.nickname}
            url={post.author.avatarUrl}
            size="large"
          />
          <div>
            <strong>{post.author.nickname}</strong>
            <span className="level-label">Lv.{post.author.level || 1}</span>
            <p>热爱拆箱和分享真实使用体验。</p>
          </div>
        </div>
        <button type="button" className="outline-button">
          + 关注
        </button>
      </section>

      <section className="aside-panel community-panel">
        <h2>来自社区</h2>
        <div className="aside-community">
          <span className="community-icon lilac">
            <Icon name="trophy" size={19} />
          </span>
          <div>
            <strong>{post.community.name}</strong>
            <p>{post.community.description || "和同好聊聊最近的新发现"}</p>
          </div>
          <Icon name="chevron-right" size={18} />
        </div>
        <Link href={`/community/${post.community.id}`} className="outline-button" style={{ textAlign: "center", display: "block" }}>
          进入社区
        </Link>
      </section>

      <section className="aside-panel related-panel">
        <div className="discovery-heading">
          <h2>相关帖子</h2>
        </div>
        {related.length ? (
          related.map((item) => (
            <Link href={`/post/${encodeURIComponent(item.id)}`} className="related-post" key={item.id}>
              {item.media[0] ? (
                <MediaImage asset={item.media[0]} alt="" className="related-media-image" />
              ) : (
                <span className="related-placeholder">
                  <Icon name="box" size={19} />
                </span>
              )}
              <span>
                <strong>{item.title}</strong>
                <small>{item.author.nickname}</small>
              </span>
            </Link>
          ))
        ) : (
          <p className="empty-rail">暂无相关帖子</p>
        )}
      </section>
    </aside>
  );
}
