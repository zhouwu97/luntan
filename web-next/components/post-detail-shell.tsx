"use client";

import Link from "next/link";
import dynamic from "next/dynamic";
import { ChangeEvent, FormEvent, MouseEvent, useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { SiteHeader } from "./site-header";
import { AppDownloadBanner } from "./app-download-banner";
import { Icon } from "./icons";
import { MediaImage } from "./media-image";
import { UserAvatar } from "./user-avatar";
import { useSession } from "./session-provider";
import { useToast } from "./toast-context";
import type { GalleryImage } from "./image-gallery-modal";
import { mediaCandidates } from "../lib/media-url";
import { fetchPost, getPostSnapshot, setPostSnapshot } from "../lib/post-memory-cache";
import {
  createComment,
  createReply,
  deleteComment,
  getCommentContext,
  getCommentReplies,
  getComments,
  getFeed,
  recordHistory,
  setCommentDislike,
  setCommentLike,
  setPostBookmark,
  setPostLike,
  setUserFollow,
  uploadImage,
} from "../lib/api/forum";
import { compactCount, formatError, relativeTime } from "../lib/format";
import type { Comment, MediaAsset, Post, SessionUser } from "../types/forum";

const ImageGalleryModal = dynamic(() => import("./image-gallery-modal").then((module) => module.ImageGalleryModal), { ssr: false });
const ReportModal = dynamic(() => import("./report-modal").then((module) => module.ReportModal), { ssr: false });

export function PostDetailShell({ id }: { id: string }) {
  const router = useRouter();
  const { user } = useSession();
  const { showToast } = useToast();
  const [post, setPost] = useState<Post | null>(() => getPostSnapshot(id));
  const [postLoading, setPostLoading] = useState(() => !getPostSnapshot(id));
  const [postError, setPostError] = useState("");

  const [comments, setComments] = useState<Comment[]>([]);
  const [commentsLoading, setCommentsLoading] = useState(true);
  const [commentsError, setCommentsError] = useState("");
  const [totalComments, setTotalComments] = useState(0);
  const [hasMoreComments, setHasMoreComments] = useState(false);
  const [loadingMoreComments, setLoadingMoreComments] = useState(false);
  const [sortOrder, setSortOrder] = useState<"hot" | "asc" | "desc">("asc");
  const [landlordOnly, setLandlordOnly] = useState(false);

  const [related, setRelated] = useState<Post[]>([]);
  const [relatedLoading, setRelatedLoading] = useState(false);

  const [mobileComposerOpen, setMobileComposerOpen] = useState(false);
  const [mobileComposerText, setMobileComposerText] = useState("");
  const [mobileFiles, setMobileFiles] = useState<File[]>([]);
  const [sendingComment, setSendingComment] = useState(false);
  const [galleryImages, setGalleryImages] = useState<GalleryImage[] | null>(null);
  const [galleryIndex, setGalleryIndex] = useState(0);
  const [reportTarget, setReportTarget] = useState<{ type: "post" | "comment"; id: string; title?: string } | null>(null);
  const [replyTarget, setReplyTarget] = useState<Comment | null>(null);
  const [targetChildCommentId, setTargetChildCommentId] = useState<string | null>(null);
  const [targetChildComment, setTargetChildComment] = useState<Comment | null>(null);

  // 1. 优先获取并展示正文（核心数据，不被评论或推荐阻塞）
  useEffect(() => {
    let mounted = true;
    const snapshot = getPostSnapshot(id, user?.id) || getPostSnapshot(id);
    if (snapshot) setPost(snapshot);
    setPostLoading(!snapshot);
    setPostError("");

    fetchPost(id, user?.id)
      .then((nextPost) => {
        if (!mounted) return;
        setPost(nextPost);
        setPostSnapshot(nextPost, user?.id);
      })
      .catch((requestError: unknown) => {
        if (!mounted) return;
        if (!snapshot) setPost(null);
        setPostError(formatError(requestError, "帖子暂时无法加载，请稍后再试"));
      })
      .finally(() => {
        if (mounted) setPostLoading(false);
      });

    return () => {
      mounted = false;
    };
  }, [id, user?.id]);

  // 2. 独立并发加载评论（带 requestId 防竞态、单一数据触发源，绝不阻塞正文）
  const commentsRequestIdRef = useRef(0);

  const fetchComments = useCallback(
    (offset = 0, append = false) => {
      if (landlordOnly && !post) return;

      const reqId = ++commentsRequestIdRef.current;
      if (!append) {
        setCommentsLoading(true);
        setCommentsError("");
      } else {
        setLoadingMoreComments(true);
      }

      getComments(id, {
        offset,
        limit: 30,
        sort: sortOrder,
        authorId: landlordOnly && post ? post.author.id : undefined,
      })
        .then((commentPage) => {
          if (reqId !== commentsRequestIdRef.current) return;
          if (append) {
            setComments((curr) => [...curr, ...commentPage.items]);
          } else {
            setComments(commentPage.items);
          }
          setTotalComments(commentPage.total);
          setHasMoreComments(commentPage.hasMore);
        })
        .catch(() => {
          if (reqId !== commentsRequestIdRef.current) return;
          if (!append) {
            setCommentsError("评论加载失败，请重试");
          } else {
            showToast("加载更多评论失败，请重试");
          }
        })
        .finally(() => {
          if (reqId === commentsRequestIdRef.current) {
            setCommentsLoading(false);
            setLoadingMoreComments(false);
          }
        });
    },
    // 关键优化：仅当开启只看楼主时才把 post?.author.id 作为依赖，杜绝正文返回引发的重复请求
    [id, sortOrder, landlordOnly, landlordOnly ? post?.author.id : undefined, showToast],
  );

  useEffect(() => {
    fetchComments(0, false);
  }, [fetchComments]);

  // 3. 异步加载相关推荐（最低优先级，静默容错）
  useEffect(() => {
    let mounted = true;
    setRelatedLoading(true);
    getFeed({ sort: "hot", limit: 5 })
      .then((feedPage) => {
        if (!mounted) return;
        setRelated(feedPage.items.filter((item) => item.id !== id).slice(0, 4));
      })
      .catch(() => {
        if (!mounted) return;
        setRelated([]);
      })
      .finally(() => {
        if (mounted) setRelatedLoading(false);
      });

    return () => {
      mounted = false;
    };
  }, [id]);

  useEffect(() => {
    if (postLoading || typeof window === "undefined" || !window.location.hash) return;
    const hash = window.location.hash;
    if (hash === "#comments") {
      const el = document.getElementById("comments");
      if (el) setTimeout(() => el.scrollIntoView({ behavior: "smooth" }), 100);
    } else if (hash.startsWith("#comment-")) {
      const commentId = hash.replace("#comment-", "");
      const existing = document.getElementById(`comment-${commentId}`);
      if (existing) {
        setTimeout(() => {
          existing.scrollIntoView({ behavior: "smooth", block: "center" });
          existing.classList.add("comment-highlight");
        }, 150);
        return;
      }

      void getCommentContext(commentId)
        .then((ctx) => {
          if (ctx.postId && ctx.postId !== id) {
            router.replace(`/post/${encodeURIComponent(ctx.postId)}#comment-${encodeURIComponent(commentId)}`);
            return;
          }
          if (ctx.isRoot) {
            if (ctx.rootComment) {
              setComments((curr) => {
                if (curr.some((c) => c.id === ctx.rootComment!.id)) return curr;
                return [...curr, ctx.rootComment!];
              });
              setTimeout(() => {
                const el = document.getElementById(`comment-${commentId}`);
                if (el) {
                  el.scrollIntoView({ behavior: "smooth", block: "center" });
                  el.classList.add("comment-highlight");
                }
              }, 200);
            }
          } else {
            if (ctx.rootComment) {
              setComments((curr) => {
                if (curr.some((c) => c.id === ctx.rootComment!.id)) return curr;
                return [...curr, ctx.rootComment!];
              });
              setTargetChildCommentId(commentId);
              setTargetChildComment(ctx.targetComment || null);
              setReplyTarget(ctx.rootComment);
            }
          }
        })
        .catch(() => undefined);
    }
  }, [postLoading]);

  useEffect(() => {
    if (user && post) void recordHistory(post.id).catch(() => undefined);
  }, [post, user]);

  function handleSortOrFilterChange(nextSort: "hot" | "asc" | "desc", nextLandlord: boolean) {
    // 状态变更驱动单一 effect 发起请求，不再手动二次拉取，彻底杜绝竞态与双重请求
    setSortOrder(nextSort);
    setLandlordOnly(nextLandlord);
  }

  function handleLoadMoreComments() {
    if (loadingMoreComments || !hasMoreComments) return;
    fetchComments(comments.length, true);
  }

  const likeRequestIdRef = useRef(0);
  const bookmarkRequestIdRef = useRef(0);
  const [likePending, setLikePending] = useState(false);
  const [bookmarkPending, setBookmarkPending] = useState(false);

  async function handleToggleLike() {
    if (!user) {
      router.push(`/login?next=${encodeURIComponent(`/post/${id}`)}`);
      return;
    }
    if (!post || likePending) return;
    setLikePending(true);
    const reqId = ++likeRequestIdRef.current;
    const next = !post.viewerState.hasLiked;
    setPost((p) =>
      p
        ? {
            ...p,
            likeCount: Math.max(0, p.likeCount + (next ? 1 : -1)),
            viewerState: { ...p.viewerState, hasLiked: next },
          }
        : p,
    );
    try {
      await setPostLike(post.id, next);
    } catch {
      if (reqId === likeRequestIdRef.current) {
        setPost((p) =>
          p
            ? {
                ...p,
                likeCount: Math.max(0, p.likeCount + (next ? -1 : 1)),
                viewerState: { ...p.viewerState, hasLiked: !next },
              }
            : p,
        );
        showToast("点赞操作失败，请重试");
      }
    } finally {
      if (reqId === likeRequestIdRef.current) {
        setLikePending(false);
      }
    }
  }

  async function handleToggleBookmark() {
    if (!user) {
      router.push(`/login?next=${encodeURIComponent(`/post/${id}`)}`);
      return;
    }
    if (!post || bookmarkPending) return;
    setBookmarkPending(true);
    const reqId = ++bookmarkRequestIdRef.current;
    const next = !post.viewerState.hasBookmarked;
    setPost((p) =>
      p
        ? {
            ...p,
            bookmarkCount: Math.max(0, p.bookmarkCount + (next ? 1 : -1)),
            viewerState: { ...p.viewerState, hasBookmarked: next },
          }
        : p,
    );
    try {
      await setPostBookmark(post.id, next);
      showToast(next ? "已收藏帖子" : "已取消收藏");
    } catch {
      if (reqId === bookmarkRequestIdRef.current) {
        setPost((p) =>
          p
            ? {
                ...p,
                bookmarkCount: Math.max(0, p.bookmarkCount + (next ? -1 : 1)),
                viewerState: { ...p.viewerState, hasBookmarked: !next },
              }
            : p,
        );
        showToast("收藏操作失败，请重试");
      }
    } finally {
      if (reqId === bookmarkRequestIdRef.current) {
        setBookmarkPending(false);
      }
    }
  }

  function handleOpenGallery(images: GalleryImage[], index = 0) {
    setGalleryImages(images);
    setGalleryIndex(index);
  }

  function handleChooseMobileFiles(event: ChangeEvent<HTMLInputElement>) {
    const next = Array.from(event.target.files || []).filter((f) => f.type.startsWith("image/"));
    event.target.value = "";
    setMobileFiles((curr) => [...curr, ...next].slice(0, 9));
  }

  async function handleMobileSubmitComment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) {
      router.push(`/login?next=${encodeURIComponent(`/post/${id}`)}`);
      return;
    }
    if ((!mobileComposerText.trim() && mobileFiles.length === 0) || sendingComment) return;
    setSendingComment(true);
    try {
      const mediaIds: string[] = [];
      for (const file of mobileFiles) {
        mediaIds.push(await uploadImage(file));
      }
      const newComment = await createComment(id, mobileComposerText.trim(), mediaIds);
      setComments((curr) => [newComment, ...curr]);
      setTotalComments((t) => t + 1);
      setMobileComposerText("");
      setMobileFiles([]);
      setMobileComposerOpen(false);
      showToast("回复发布成功！");
    } catch (reqErr) {
      showToast(formatError(reqErr, "回复失败，请重试"));
    } finally {
      setSendingComment(false);
    }
  }

  function handleShareLink() {
    if (typeof window !== "undefined" && navigator.clipboard) {
      void navigator.clipboard.writeText(window.location.href);
      showToast("已复制帖子链接");
    }
  }

  if (postLoading && !post) {
    return (
      <>
        <SiteHeader />
        <main className="page-frame post-detail-page-frame">
          <div className="detail-grid">
            <section className="detail-main">
              <div className="back-link detail-back desktop-only" style={{ opacity: 0.6 }}>
                <Icon name="chevron-left" size={17} />
                <span>正在进入讨论…</span>
              </div>
              <article className="detail-article" style={{ pointerEvents: "none" }}>
                <header className="detail-author">
                  <div className="avatar avatar-large" style={{ background: "linear-gradient(110deg, #f1f5f9 8%, #e2e8f0 18%, #f1f5f9 33%)", backgroundSize: "200% 100%", animation: "shimmer 1.5s infinite" }} />
                  <div className="post-author" style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                    <div style={{ width: 120, height: 16, background: "#e2e8f0", borderRadius: 4, animation: "shimmer 1.5s infinite" }} />
                    <div style={{ width: 90, height: 12, background: "#f1f5f9", borderRadius: 4 }} />
                  </div>
                </header>
                <div style={{ width: "75%", height: 28, background: "#e2e8f0", borderRadius: 6, margin: "18px 0 14px", animation: "shimmer 1.5s infinite" }} />
                <div className="detail-body" style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                  <div style={{ width: "100%", height: 16, background: "#f1f5f9", borderRadius: 4 }} />
                  <div style={{ width: "96%", height: 16, background: "#f1f5f9", borderRadius: 4 }} />
                  <div style={{ width: "88%", height: 16, background: "#f1f5f9", borderRadius: 4 }} />
                  <div style={{ width: "60%", height: 16, background: "#f1f5f9", borderRadius: 4 }} />
                </div>
              </article>
            </section>
            <aside className="detail-aside desktop-only">
              <section className="aside-panel" style={{ height: 180, animation: "shimmer 1.5s infinite" }} />
            </aside>
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
            <Icon name="box" size={32} />
            <h1>帖子不存在或已被删除</h1>
            <p>{postError || "你访问的帖子可能已被移动或设为私密。"}</p>
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
      <SiteHeader />

      {/* 移动端详情顶部导航 */}
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
          aria-label="复制链接与分享"
          onClick={handleShareLink}
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

            {postError && <div className="data-note">{postError}</div>}

            <PostArticle
              post={post}
              user={user}
              onRequireAuth={() => router.push(`/login?next=${encodeURIComponent(`/post/${id}`)}`)}
              onOpenGallery={handleOpenGallery}
              onOpenReport={() => setReportTarget({ type: "post", id: post.id, title: post.title })}
              onToggleLike={handleToggleLike}
              onToggleBookmark={handleToggleBookmark}
              likePending={likePending}
              bookmarkPending={bookmarkPending}
            />

            <CommentsSection
              post={post}
              comments={comments}
              setComments={setComments}
              totalComments={totalComments}
              setTotalComments={setTotalComments}
              hasMoreComments={hasMoreComments}
              loadingMoreComments={loadingMoreComments}
              commentsLoading={commentsLoading}
              commentsError={commentsError}
              onRetryComments={() => fetchComments(0, false)}
              sortOrder={sortOrder}
              landlordOnly={landlordOnly}
              onSortOrFilterChange={handleSortOrFilterChange}
              onLoadMoreComments={handleLoadMoreComments}
              user={user}
              onRequireAuth={() => router.push(`/login?next=${encodeURIComponent(`/post/${id}`)}`)}
              onOpenGallery={handleOpenGallery}
              onReportComment={(c) =>
                setReportTarget({ type: "comment", id: c.id, title: c.content ? c.content.slice(0, 30) : "评论" })
              }
              replyTarget={replyTarget}
              setReplyTarget={setReplyTarget}
              targetChildCommentId={targetChildCommentId}
              targetChildComment={targetChildComment}
            />
          </section>

          {/* 桌面端侧边作者与相关推荐 */}
          <DetailAside post={post} related={related} user={user} />
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
          <a href="#comments" className="comp-stat" aria-label="查看评论">
            <Icon name="message" size={18} />
            {compactCount(totalComments)}
          </a>
          <button
            type="button"
            className={`comp-stat stat${post.viewerState.hasLiked ? " selected" : ""}`}
            onClick={handleToggleLike}
            disabled={likePending}
            aria-label={post.viewerState.hasLiked ? "已点赞" : "点赞"}
          >
            <Icon name="heart" size={18} />
            {compactCount(post.likeCount)}
          </button>
          <button
            type="button"
            className={`comp-stat stat${post.viewerState.hasBookmarked ? " selected" : ""}`}
            onClick={handleToggleBookmark}
            disabled={bookmarkPending}
            aria-label={post.viewerState.hasBookmarked ? "已收藏" : "收藏"}
          >
            <Icon name="bookmark" size={18} />
            {compactCount(post.bookmarkCount)}
          </button>
        </div>
      </div>

      {/* 移动端弹出发评抽屉 */}
      {mobileComposerOpen && (
        <div
          className="composer-sheet-overlay"
          onClick={(e) => {
            if (e.target === e.currentTarget) setMobileComposerOpen(false);
          }}
        >
          <div className="composer-sheet">
            <div className="composer-sheet-handle" />
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

              {mobileFiles.length > 0 && (
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 8 }}>
                  {mobileFiles.map((file, idx) => (
                    <div
                      key={idx}
                      style={{
                        position: "relative",
                        width: 54,
                        height: 54,
                        borderRadius: 8,
                        overflow: "hidden",
                      }}
                    >
                      <img
                        src={URL.createObjectURL(file)}
                        alt=""
                        style={{ width: "100%", height: "100%", objectFit: "cover" }}
                      />
                      <button
                        type="button"
                        onClick={() => setMobileFiles((files) => files.filter((_, i) => i !== idx))}
                        style={{
                          position: "absolute",
                          top: 2,
                          right: 2,
                          background: "rgba(0,0,0,0.6)",
                          color: "#fff",
                          border: 0,
                          borderRadius: "50%",
                          width: 18,
                          height: 18,
                          fontSize: 10,
                          display: "grid",
                          placeItems: "center",
                          cursor: "pointer",
                        }}
                      >
                        ×
                      </button>
                    </div>
                  ))}
                </div>
              )}

              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  marginTop: 10,
                }}
              >
                <label
                  style={{
                    display: "inline-flex",
                    alignItems: "center",
                    gap: 4,
                    color: "#3b82f6",
                    fontSize: 13,
                    cursor: "pointer",
                  }}
                >
                  <Icon name="image" size={18} />
                  <span>图片 ({mobileFiles.length}/9)</span>
                  <input
                    type="file"
                    accept="image/*"
                    multiple
                    style={{ display: "none" }}
                    onChange={handleChooseMobileFiles}
                    disabled={mobileFiles.length >= 9}
                  />
                </label>
                <div style={{ display: "flex", gap: 10 }}>
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
                    disabled={(!mobileComposerText.trim() && mobileFiles.length === 0) || sendingComment}
                  >
                    {sendingComment ? "发送中…" : "发送"}
                  </button>
                </div>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* 图片全屏画廊查看器 */}
      {galleryImages && (
        <ImageGalleryModal
          images={galleryImages}
          initialIndex={galleryIndex}
          onClose={() => setGalleryImages(null)}
        />
      )}

      {/* 举报弹层 */}
      {reportTarget && (
        <ReportModal
          targetType={reportTarget.type}
          targetId={reportTarget.id}
          targetTitle={reportTarget.title}
          onClose={() => setReportTarget(null)}
        />
      )}

      <AppDownloadBanner />
    </>
  );
}

function PostArticle({
  post,
  user,
  onRequireAuth,
  onOpenGallery,
  onOpenReport,
  onToggleLike,
  onToggleBookmark,
  likePending = false,
  bookmarkPending = false,
}: {
  post: Post;
  user: SessionUser | null;
  onRequireAuth: () => void;
  onOpenGallery: (images: GalleryImage[], index?: number) => void;
  onOpenReport: () => void;
  onToggleLike: () => void;
  onToggleBookmark: () => void;
  likePending?: boolean;
  bookmarkPending?: boolean;
}) {
  const articleImages: GalleryImage[] = post.media.map((item) => ({
    url: item.detailUrl || item.url || item.originalUrl || "",
    alt: item.altText || post.title,
    detailUrl: item.detailUrl,
    originalUrl: item.originalUrl || item.url,
    thumbUrl: item.thumbUrl,
    sources: mediaCandidates(item, "detail"),
  }));

  return (
    <article className="detail-article">
      <header className="detail-author">
        <Link href={`/user/${encodeURIComponent(post.author.id)}`}>
          <UserAvatar
            userId={post.author.id}
            name={post.author.nickname}
            url={post.author.avatarUrl}
            className="post-avatar"
          />
        </Link>
        <div className="post-author">
          <Link href={`/user/${encodeURIComponent(post.author.id)}`} className="author-line">
            <span className="author-name">{post.author.nickname}</span>
            <span className="lv">Lv.{post.author.level || 1}</span>
          </Link>
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
            <div
              key={index}
              style={{ cursor: "pointer" }}
              onClick={() => onOpenGallery(articleImages, index)}
            >
              <MediaImage asset={asset} preferred="detail" alt={`${post.title} 图片 ${index + 1}`} />
            </div>
          ))}
        </div>
      )}

      <div className="detail-stats">
        <a href="#comments" style={{ display: "inline-flex", alignItems: "center", gap: 5, color: "inherit", textDecoration: "none" }}>
          <Icon name="message" size={15} />
          {compactCount(post.commentCount)} 评论
        </a>
        <button
          type="button"
          className={`stat${post.viewerState.hasLiked ? " selected" : ""}`}
          onClick={onToggleLike}
          disabled={likePending}
          style={{ background: "none", border: "none", cursor: likePending ? "not-allowed" : "pointer" }}
        >
          <Icon name="heart" size={15} />
          {compactCount(post.likeCount)} 点赞
        </button>
        <button
          type="button"
          className={`stat${post.viewerState.hasBookmarked ? " selected" : ""}`}
          onClick={onToggleBookmark}
          disabled={bookmarkPending}
          style={{ background: "none", border: "none", cursor: bookmarkPending ? "not-allowed" : "pointer" }}
        >
          <Icon name="bookmark" size={15} />
          {compactCount(post.bookmarkCount)} 收藏
        </button>
        <span>
          <Icon name="eye" size={15} />
          {compactCount(post.viewCount)} 浏览
        </span>
        <button
          type="button"
          className="stat"
          onClick={() => {
            if (!user) return onRequireAuth();
            onOpenReport();
          }}
          style={{ background: "none", border: "none", cursor: "pointer" }}
        >
          <Icon name="info" size={15} />
          举报
        </button>
      </div>
    </article>
  );
}

function CommentsSection({
  post,
  comments,
  setComments,
  totalComments,
  setTotalComments,
  hasMoreComments,
  loadingMoreComments,
  commentsLoading,
  commentsError,
  onRetryComments,
  sortOrder,
  landlordOnly,
  onSortOrFilterChange,
  onLoadMoreComments,
  user,
  onRequireAuth,
  onOpenGallery,
  onReportComment,
  replyTarget,
  setReplyTarget,
  targetChildCommentId,
  targetChildComment,
}: {
  post: Post;
  comments: Comment[];
  setComments: React.Dispatch<React.SetStateAction<Comment[]>>;
  totalComments: number;
  setTotalComments: React.Dispatch<React.SetStateAction<number>>;
  hasMoreComments: boolean;
  loadingMoreComments: boolean;
  commentsLoading?: boolean;
  commentsError?: string;
  onRetryComments?: () => void;
  sortOrder: "hot" | "asc" | "desc";
  landlordOnly: boolean;
  onSortOrFilterChange: (nextSort: "hot" | "asc" | "desc", nextLandlord: boolean) => void;
  onLoadMoreComments: () => void;
  user: SessionUser | null;
  onRequireAuth: () => void;
  onOpenGallery: (images: GalleryImage[], index?: number) => void;
  onReportComment: (c: Comment) => void;
  replyTarget: Comment | null;
  setReplyTarget: React.Dispatch<React.SetStateAction<Comment | null>>;
  targetChildCommentId?: string | null;
  targetChildComment?: Comment | null;
}) {
  const [content, setContent] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  function handleChooseFiles(e: ChangeEvent<HTMLInputElement>) {
    const next = Array.from(e.target.files || []).filter((f) => f.type.startsWith("image/"));
    e.target.value = "";
    setFiles((curr) => [...curr, ...next].slice(0, 9));
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) return onRequireAuth();
    if ((!content.trim() && files.length === 0) || busy) return;
    setBusy(true);
    setMessage("");
    try {
      const mediaIds: string[] = [];
      for (const file of files) {
        mediaIds.push(await uploadImage(file));
      }
      const next = await createComment(post.id, content.trim(), mediaIds);
      setComments((current) => [next, ...current]);
      setTotalComments((t) => t + 1);
      setContent("");
      setFiles([]);
    } catch (requestError) {
      setMessage(formatError(requestError, "评论发送失败，请稍后重试"));
    } finally {
      setBusy(false);
    }
  }

  async function handleDeleteComment(commentId: string) {
    if (!window.confirm("确定要删除这条评论吗？")) return;
    try {
      await deleteComment(commentId);
      setComments((curr) => curr.filter((c) => c.id !== commentId));
      setTotalComments((t) => Math.max(0, t - 1));
    } catch {
      alert("删除评论失败，请重试");
    }
  }

  return (
    <section className="comments-wrap" id="comments" aria-label="帖子评论区">
      <div className="comments-head">
        <h2 className="comm-title">评论 ({totalComments})</h2>
        <span className="comm-sub">全部讨论</span>
      </div>

      {/* 排序与筛选条 */}
      <div className="comment-tools">
        <div className="chips">
          <button
            type="button"
            className={`chip${sortOrder === "hot" ? " active" : ""}`}
            onClick={() => onSortOrFilterChange("hot", landlordOnly)}
          >
            热门
          </button>
          <button
            type="button"
            className={`chip${sortOrder === "asc" ? " active" : ""}`}
            onClick={() => onSortOrFilterChange("asc", landlordOnly)}
          >
            最早
          </button>
          <button
            type="button"
            className={`chip${sortOrder === "desc" ? " active" : ""}`}
            onClick={() => onSortOrFilterChange("desc", landlordOnly)}
          >
            最新
          </button>
        </div>
        <button
          type="button"
          className={`landlord${landlordOnly ? " active" : ""}`}
          onClick={() => onSortOrFilterChange(sortOrder, !landlordOnly)}
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
            placeholder={user ? "写下你的评价、拆箱感受或回复…" : "登录后参与回复"}
            rows={2}
            onFocus={() => {
              if (!user) onRequireAuth();
            }}
          />

          {files.length > 0 && (
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", padding: "6px 12px" }}>
              {files.map((file, idx) => (
                <div
                  key={idx}
                  style={{
                    position: "relative",
                    width: 52,
                    height: 52,
                    borderRadius: 8,
                    overflow: "hidden",
                    border: "1px solid #dce8f3",
                  }}
                >
                  <img
                    src={URL.createObjectURL(file)}
                    alt=""
                    style={{ width: "100%", height: "100%", objectFit: "cover" }}
                  />
                  <button
                    type="button"
                    onClick={() => setFiles((curr) => curr.filter((_, i) => i !== idx))}
                    style={{
                      position: "absolute",
                      top: 2,
                      right: 2,
                      background: "rgba(0,0,0,0.6)",
                      color: "#fff",
                      border: 0,
                      borderRadius: "50%",
                      width: 16,
                      height: 16,
                      fontSize: 10,
                      display: "grid",
                      placeItems: "center",
                      cursor: "pointer",
                    }}
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>
          )}

          <div className="composer-footer">
            <label
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 5,
                color: "#64748b",
                fontSize: 13,
                cursor: "pointer",
                padding: "4px 8px",
              }}
            >
              <Icon name="image" size={17} />
              <span>上传图片 ({files.length}/9)</span>
              <input
                type="file"
                accept="image/*"
                multiple
                style={{ display: "none" }}
                onChange={handleChooseFiles}
                disabled={files.length >= 9}
              />
            </label>
            <button
              type="submit"
              className="reply-submit"
              disabled={(!content.trim() && files.length === 0) || busy}
            >
              {busy ? "发送中…" : "发布回复"}
            </button>
          </div>
        </div>
      </form>

      {message && <div className="form-error">{message}</div>}

      <div className="comment-list">
        {commentsLoading && !comments.length ? (
          <div className="comment-loading-skeleton" style={{ display: "grid", gap: 14, padding: "12px 0" }}>
            <div style={{ height: 90, background: "#f8fafc", borderRadius: 12, border: "1px solid var(--line)", animation: "shimmer 1.5s infinite" }} />
            <div style={{ height: 90, background: "#f8fafc", borderRadius: 12, border: "1px solid var(--line)", animation: "shimmer 1.5s infinite" }} />
          </div>
        ) : commentsError && !comments.length ? (
          <div className="empty-state" style={{ padding: "30px 0" }}>
            <Icon name="info" size={24} />
            <p>{commentsError}</p>
            {onRetryComments && (
              <button
                type="button"
                className="outline-button"
                onClick={onRetryComments}
                style={{ marginTop: 10, fontSize: 13 }}
              >
                重试加载评论
              </button>
            )}
          </div>
        ) : comments.length ? (
          comments.map((comment: Comment) => (
            <CommentRow
              key={comment.id}
              comment={comment}
              user={user}
              onRequireAuth={onRequireAuth}
              onReply={() => setReplyTarget(comment)}
              onDelete={() => handleDeleteComment(comment.id)}
              onOpenGallery={onOpenGallery}
              onReport={() => {
                if (!user) return onRequireAuth();
                onReportComment(comment);
              }}
            />
          ))
        ) : (
          <div className="empty-state" style={{ padding: "30px 0" }}>
            <Icon name="message" size={24} />
            <p>{landlordOnly ? "楼主还没有发表评论" : "还没有回复，来做第一个分享的人吧！"}</p>
          </div>
        )}

        {hasMoreComments && (
          <div style={{ display: "flex", justifyContent: "center", marginTop: 18, marginBottom: 18 }}>
            <button
              type="button"
              className="outline-button"
              onClick={onLoadMoreComments}
              disabled={loadingMoreComments}
              style={{ minWidth: 140 }}
            >
              {loadingMoreComments ? "正在加载…" : "加载更多评论"}
            </button>
          </div>
        )}
      </div>

      {replyTarget && (
        <CommentReplyModal
          root={replyTarget}
          targetCommentId={targetChildCommentId || undefined}
          targetComment={targetChildComment || undefined}
          user={user}
          onRequireAuth={onRequireAuth}
          onClose={() => setReplyTarget(null)}
          onOpenGallery={onOpenGallery}
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
  onDelete,
  onOpenGallery,
  onReport,
}: {
  comment: Comment;
  user: SessionUser | null;
  onRequireAuth: () => void;
  onReply: () => void;
  onDelete: () => void;
  onOpenGallery: (images: GalleryImage[], index?: number) => void;
  onReport: () => void;
}) {
  const [liked, setLiked] = useState(comment.viewerState.hasLiked);
  const [disliked, setDisliked] = useState(comment.viewerState.hasDisliked);
  const [count, setCount] = useState(comment.likeCount);
  const [dislikeCount, setDislikeCount] = useState(comment.dislikeCount || 0);

  async function like(event: MouseEvent<HTMLButtonElement>) {
    event.preventDefault();
    if (!user) return onRequireAuth();
    const next = !liked;
    setLiked(next);
    setCount((value) => value + (next ? 1 : -1));
    if (next && disliked) {
      setDisliked(false);
      setDislikeCount((val) => Math.max(0, val - 1));
    }
    try {
      await setCommentLike(comment.id, next);
    } catch {
      setLiked(!next);
      setCount((value) => value + (next ? -1 : 1));
    }
  }

  async function dislike(event: MouseEvent<HTMLButtonElement>) {
    event.preventDefault();
    if (!user) return onRequireAuth();
    const next = !disliked;
    setDisliked(next);
    setDislikeCount((value) => value + (next ? 1 : -1));
    if (next && liked) {
      setLiked(false);
      setCount((val) => Math.max(0, val - 1));
    }
    try {
      await setCommentDislike(comment.id, next);
    } catch {
      setDisliked(!next);
      setDislikeCount((value) => value + (next ? -1 : 1));
    }
  }

function CommentMediaThumbnail({
  asset,
  alt,
  onClick,
}: {
  asset: MediaAsset;
  alt: string;
  onClick: (e: MouseEvent) => void;
}) {
  // 评论详情允许用原图做最终容灾；首页 Feed 使用的 MediaImage 不走这条链。
  const candidates = [...new Set([
    ...mediaCandidates(asset, "thumb"),
    ...mediaCandidates(asset, "detail"),
    ...mediaCandidates(asset, "original"),
  ])];
  const [candidateIdx, setCandidateIdx] = useState(0);
  const src = candidates[candidateIdx] || asset.thumbUrl || asset.url;
  const isFailed = candidateIdx >= candidates.length && candidates.length > 0;

  if (isFailed) {
    return (
      <div
        className="comment-media-thumb comment-media-failed"
        style={{
          width: 80,
          height: 80,
          borderRadius: 8,
          background: "var(--color-bg-secondary, #f1f5f9)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: "var(--color-text-secondary, #94a3b8)",
          cursor: "pointer",
        }}
        onClick={onClick}
        title="图片加载失败，点击尝试打开画廊"
      >
        <Icon name="image" size={20} />
      </div>
    );
  }

  return (
    <img
      src={src}
      alt={alt}
      style={{
        width: 80,
        height: 80,
        borderRadius: 8,
        objectFit: "cover",
        cursor: "pointer",
      }}
      onError={() => {
        if (candidateIdx + 1 < candidates.length) {
          setCandidateIdx((i) => i + 1);
        } else {
          setCandidateIdx(candidates.length);
        }
      }}
      onClick={onClick}
    />
  );
}

  const commentImages: GalleryImage[] = (comment.media || []).map((item) => ({
    url: item.detailUrl || item.url || item.originalUrl || "",
    alt: item.altText || "评论配图",
    detailUrl: item.detailUrl,
    originalUrl: item.originalUrl || item.url,
    thumbUrl: item.thumbUrl,
    sources: mediaCandidates(item, "detail"),
  }));

  const canDelete = Boolean(
    user &&
      (user.id === comment.author.id || user.role === "admin" || user.role === "moderator"),
  );

  return (
    <article className="comment-card" id={`comment-${comment.id}`}>
      <Link href={`/user/${encodeURIComponent(comment.author.id)}`}>
        <UserAvatar
          userId={comment.author.id}
          name={comment.author.nickname}
          url={comment.author.avatarUrl}
          className="comm-avatar"
        />
      </Link>
      <div className="comm-main">
        <div className="comm-head">
          <Link href={`/user/${encodeURIComponent(comment.author.id)}`} className="comm-name">
            {comment.author.nickname}
          </Link>
          <span className="comm-lv">Lv.{comment.author.level || 1}</span>
          <span className="comm-floor">#{comment.floor || "1"}</span>
        </div>
        <div className="comm-time">{relativeTime(comment.createdAt)}</div>
        <p className="comm-text">{comment.content}</p>

        {comment.media && comment.media.length > 0 && (
          <div
            className="comment-media-grid"
            style={{
              display: "flex",
              gap: 8,
              flexWrap: "wrap",
              marginTop: 8,
              marginBottom: 8,
            }}
          >
            {comment.media.map((asset, idx) => (
              <CommentMediaThumbnail
                key={asset.id || idx}
                asset={asset}
                alt={asset.altText || `评论图片 ${idx + 1}`}
                onClick={(e) => {
                  e.stopPropagation();
                  onOpenGallery(commentImages, idx);
                }}
              />
            ))}
          </div>
        )}

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
            aria-label={liked ? "取消赞" : "点赞"}
          >
            <Icon name="heart" size={14} />
            <span>{count}</span>
          </button>
          <button
            type="button"
            className={`comm-act${disliked ? " selected" : ""}`}
            onClick={dislike}
            aria-label={disliked ? "取消踩" : "点踩"}
          >
            <Icon name="dislike" size={14} />
            <span>{dislikeCount > 0 ? dislikeCount : "踩"}</span>
          </button>
          <button type="button" className="comm-act" onClick={onReply}>
            <Icon name="message" size={14} />
            <span>回复</span>
          </button>
          <button type="button" className="comm-act" onClick={onReport}>
            <Icon name="info" size={13} />
            <span>举报</span>
          </button>
          {canDelete && (
            <button
              type="button"
              className="comm-act"
              style={{ color: "#ef4444" }}
              onClick={onDelete}
            >
              <Icon name="close" size={12} />
              <span>删除</span>
            </button>
          )}
        </div>
      </div>
    </article>
  );
}

function CommentReplyModal({
  root,
  targetCommentId,
  targetComment,
  user,
  onRequireAuth,
  onClose,
  onOpenGallery,
}: {
  root: Comment;
  targetCommentId?: string;
  targetComment?: Comment;
  user: SessionUser | null;
  onRequireAuth: () => void;
  onClose: () => void;
  onOpenGallery: (images: GalleryImage[], index?: number) => void;
}) {
  const [replies, setReplies] = useState<Comment[]>([]);
  const [nextCursor, setNextCursor] = useState<string>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [content, setContent] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    let active = true;
    void getCommentReplies(root.id)
      .then((page) => {
        if (!active) return;
        let items = page.items;
        if (targetCommentId && targetComment && !items.some((item) => item.id === targetCommentId)) {
          items = [...items, targetComment];
        }
        setReplies(items);
        setNextCursor(page.nextCursor);
        setHasMore(page.hasMore);
      })
      .catch(() => {
        if (active) {
          if (targetCommentId && targetComment) {
            setReplies([targetComment]);
          } else {
            setMessage("回复加载失败，请重试");
          }
        }
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [root.id, targetCommentId, targetComment]);

  useEffect(() => {
    if (!loading && targetCommentId) {
      const timer = setTimeout(() => {
        const el = document.getElementById(`comment-${targetCommentId}`);
        if (el) {
          el.scrollIntoView({ behavior: "smooth", block: "center" });
          el.classList.add("comment-highlight");
        }
      }, 150);
      return () => clearTimeout(timer);
    }
  }, [loading, targetCommentId, replies]);

  async function handleLoadMoreReplies() {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const page = await getCommentReplies(root.id, nextCursor);
      setReplies((curr) => {
        const ids = new Set(curr.map((item) => item.id));
        return [...curr, ...page.items.filter((item) => !ids.has(item.id))];
      });
      setNextCursor(page.nextCursor);
      setHasMore(page.hasMore);
    } catch {
      setMessage("加载更多回复失败");
    } finally {
      setLoadingMore(false);
    }
  }

  function handleChooseFiles(e: ChangeEvent<HTMLInputElement>) {
    const next = Array.from(e.target.files || []).filter((f) => f.type.startsWith("image/"));
    e.target.value = "";
    setFiles((curr) => [...curr, ...next].slice(0, 9));
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) return onRequireAuth();
    if ((!content.trim() && files.length === 0) || busy) return;
    setBusy(true);
    try {
      const mediaIds: string[] = [];
      for (const file of files) {
        mediaIds.push(await uploadImage(file));
      }
      const next = await createReply(root.id, content.trim(), undefined, mediaIds);
      setReplies((current) => [...current, next]);
      setContent("");
      setFiles([]);
    } catch (requestError) {
      setMessage(formatError(requestError, "回复发送失败，请稍后重试"));
    } finally {
      setBusy(false);
    }
  }

  async function handleDeleteReply(replyId: string) {
    if (!window.confirm("确定要删除这条回复吗？")) return;
    try {
      await deleteComment(replyId);
      setReplies((curr) => curr.filter((r) => r.id !== replyId));
    } catch {
      alert("删除回复失败，请重试");
    }
  }

  const rootImages: GalleryImage[] = (root.media || []).map((item) => ({
    url: item.detailUrl || item.url || "",
    alt: "楼层配图",
    originalUrl: item.originalUrl || item.url,
  }));

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
            <Link href={`/user/${encodeURIComponent(root.author.id)}`}>
              <UserAvatar
                userId={root.author.id}
                name={root.author.nickname}
                url={root.author.avatarUrl}
                className="avatar-comment"
              />
            </Link>
            <div>
              <Link href={`/user/${encodeURIComponent(root.author.id)}`}>
                <strong>{root.author.nickname}</strong>
              </Link>
              <p>{root.content}</p>
              {rootImages.length > 0 && (
                <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginTop: 6 }}>
                  {rootImages.map((img, idx) => (
                    <img
                      key={idx}
                      src={img.url}
                      alt=""
                      style={{ width: 64, height: 64, borderRadius: 6, objectFit: "cover", cursor: "pointer" }}
                      onClick={() => onOpenGallery(rootImages, idx)}
                    />
                  ))}
                </div>
              )}
            </div>
          </div>

          {loading ? (
            <div className="comment-empty">正在加载回复…</div>
          ) : (
            replies.map((reply) => {
              const replyImages: GalleryImage[] = (reply.media || []).map((item) => ({
                url: item.detailUrl || item.url || "",
                alt: "回复配图",
                originalUrl: item.originalUrl || item.url,
              }));
              const canDelete = Boolean(
                user &&
                  (user.id === reply.author.id || user.role === "admin" || user.role === "moderator"),
              );

              return (
                <div className="comment-reply-item" key={reply.id} id={`comment-${reply.id}`}>
                  <Link href={`/user/${encodeURIComponent(reply.author.id)}`}>
                    <UserAvatar
                      userId={reply.author.id}
                      name={reply.author.nickname}
                      url={reply.author.avatarUrl}
                      className="avatar-comment"
                    />
                  </Link>
                  <div style={{ flex: 1 }}>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                      <div>
                        <Link href={`/user/${encodeURIComponent(reply.author.id)}`}>
                          <strong>{reply.author.nickname}</strong>
                        </Link>
                        <span className="comment-time">{relativeTime(reply.createdAt)}</span>
                      </div>
                      {canDelete && (
                        <button
                          type="button"
                          onClick={() => handleDeleteReply(reply.id)}
                          style={{ color: "#ef4444", background: "none", border: 0, fontSize: 12, cursor: "pointer" }}
                        >
                          删除
                        </button>
                      )}
                    </div>
                    <p>{reply.content}</p>
                    {replyImages.length > 0 && (
                      <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginTop: 6 }}>
                        {replyImages.map((img, idx) => (
                          <img
                            key={idx}
                            src={img.url}
                            alt=""
                            style={{ width: 60, height: 60, borderRadius: 6, objectFit: "cover", cursor: "pointer" }}
                            onClick={() => onOpenGallery(replyImages, idx)}
                          />
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              );
            })
          )}

          {hasMore && (
            <div style={{ display: "flex", justifyContent: "center", padding: "12px 0" }}>
              <button
                type="button"
                className="outline-button"
                onClick={handleLoadMoreReplies}
                disabled={loadingMore}
                style={{ minWidth: 120 }}
              >
                {loadingMore ? "正在加载…" : "加载更多回复"}
              </button>
            </div>
          )}
        </div>

        {files.length > 0 && (
          <div style={{ display: "flex", gap: 6, padding: "4px 16px" }}>
            {files.map((file, idx) => (
              <div key={idx} style={{ position: "relative", width: 44, height: 44, borderRadius: 6, overflow: "hidden" }}>
                <img src={URL.createObjectURL(file)} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                <button
                  type="button"
                  onClick={() => setFiles((f) => f.filter((_, i) => i !== idx))}
                  style={{
                    position: "absolute",
                    top: 1,
                    right: 1,
                    background: "rgba(0,0,0,0.6)",
                    color: "#fff",
                    border: 0,
                    borderRadius: "50%",
                    width: 14,
                    height: 14,
                    fontSize: 9,
                    cursor: "pointer",
                  }}
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        )}

        <form className="comment-reply-composer" onSubmit={submit}>
          <label style={{ cursor: "pointer", display: "grid", placeItems: "center", padding: "0 6px", color: "#64748b" }}>
            <Icon name="image" size={19} />
            <input type="file" accept="image/*" multiple style={{ display: "none" }} onChange={handleChooseFiles} disabled={files.length >= 9} />
          </label>
          <input
            value={content}
            onChange={(event) => setContent(event.target.value)}
            placeholder="友善地回复一句…"
          />
          <button type="submit" disabled={(!content.trim() && files.length === 0) || busy}>
            {busy ? "发送中" : "发送"}
          </button>
        </form>
        {message && <div className="form-error">{message}</div>}
      </section>
    </div>
  );
}

function DetailAside({ post, related, user }: { post: Post; related: Post[]; user: SessionUser | null }) {
  const router = useRouter();
  const { showToast } = useToast();
  const [following, setFollowing] = useState(post.viewerState.isFollowingAuthor);
  const [followBusy, setFollowBusy] = useState(false);

  async function handleToggleFollow() {
    if (!user) {
      router.push(`/login?next=${encodeURIComponent(`/post/${post.id}`)}`);
      return;
    }
    if (followBusy) return;
    setFollowBusy(true);
    const next = !following;
    setFollowing(next);
    try {
      await setUserFollow(post.author.id, next);
      showToast(next ? "已关注作者" : "已取消关注");
    } catch {
      setFollowing(!next);
      showToast("关注操作失败，请重试");
    } finally {
      setFollowBusy(false);
    }
  }

  const isSelf = Boolean(user && user.id === post.author.id);

  return (
    <aside className="detail-aside desktop-only">
      <section className="aside-panel author-panel">
        <h2>作者信息</h2>
        <div className="aside-author">
          <Link href={`/user/${encodeURIComponent(post.author.id)}`}>
            <UserAvatar
              userId={post.author.id}
              name={post.author.nickname}
              url={post.author.avatarUrl}
              size="large"
            />
          </Link>
          <div>
            <Link href={`/user/${encodeURIComponent(post.author.id)}`}>
              <strong>{post.author.nickname}</strong>
            </Link>
            <span className="level-label">Lv.{post.author.level || 1}</span>
            <p>热爱拆箱和分享真实使用体验。</p>
          </div>
        </div>
        {!isSelf && (
          <button
            type="button"
            className={`outline-button${following ? " active" : ""}`}
            onClick={handleToggleFollow}
            disabled={followBusy}
            style={{
              width: "100%",
              marginTop: 12,
              background: following ? "#eff6ff" : undefined,
              borderColor: following ? "#3b82f6" : undefined,
              color: following ? "#2563eb" : undefined,
            }}
          >
            {followBusy ? "处理中…" : following ? "已关注" : "+ 关注"}
          </button>
        )}
      </section>

      <section className="aside-panel community-panel">
        <h2>来自社区</h2>
        <Link
          href={`/?community=${encodeURIComponent(post.community.id)}`}
          className="aside-community"
          style={{ textDecoration: "none", color: "inherit" }}
        >
          <span className="community-icon lilac">
            <Icon name="trophy" size={19} />
          </span>
          <div style={{ flex: 1 }}>
            <strong>{post.community.name}</strong>
            <p>{post.community.description || "和同好聊聊最近的新发现"}</p>
          </div>
          <Icon name="chevron-right" size={18} />
        </Link>
      </section>

      {related.length > 0 && (
        <section className="aside-panel">
          <h2>相关讨论</h2>
          <div className="related-list">
            {related.map((item) => (
              <Link
                key={item.id}
                href={`/post/${encodeURIComponent(item.id)}`}
                className="related-item"
              >
                <strong>{item.title}</strong>
                <div>
                  <span>{item.author.nickname}</span>
                  <span>{compactCount(item.commentCount)} 回复</span>
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}
    </aside>
  );
}
