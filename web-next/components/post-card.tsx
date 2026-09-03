"use client";

import Link from "next/link";
import { MouseEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "./icons";
import { MediaImage } from "./media-image";
import { UserAvatar } from "./user-avatar";
import { useToast } from "./toast-context";
import { ImageGalleryModal, type GalleryImage } from "./image-gallery-modal";
import { ReportModal } from "./report-modal";
import type { Post, SessionUser } from "../types/forum";
import { deletePost, setPostBookmark, setPostLike } from "../lib/api/forum";
import { compactCount, relativeTime } from "../lib/format";

function stop(event: MouseEvent) {
  event.preventDefault();
  event.stopPropagation();
}

export function PostCard({
  post,
  user,
  contextMeta,
}: {
  post: Post;
  user: SessionUser | null;
  contextMeta?: string;
}) {
  const router = useRouter();
  const { showToast } = useToast();
  const [liked, setLiked] = useState(post.viewerState.hasLiked);
  const [bookmarked, setBookmarked] = useState(post.viewerState.hasBookmarked);
  const [likeCount, setLikeCount] = useState(post.likeCount);
  const [busy, setBusy] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [galleryIndex, setGalleryIndex] = useState<number | null>(null);
  const [reportOpen, setReportOpen] = useState(false);
  const [deleted, setDeleted] = useState(false);

  if (deleted) return null;

  const galleryImages: GalleryImage[] = post.media.map((item) => ({
    url: item.detailUrl || item.url || "",
    alt: item.altText || post.title,
    originalUrl: item.originalUrl || item.url,
  }));

  async function handleLike(event: MouseEvent<HTMLButtonElement>) {
    stop(event);
    if (!user) {
      router.push("/login");
      return;
    }
    if (busy) return;
    const next = !liked;
    setLiked(next);
    setLikeCount((value) => Math.max(0, value + (next ? 1 : -1)));
    setBusy(true);
    try {
      await setPostLike(post.id, next);
    } catch {
      setLiked(!next);
      setLikeCount((value) => Math.max(0, value + (next ? -1 : 1)));
      showToast("点赞操作失败，请重试");
    } finally {
      setBusy(false);
    }
  }

  async function handleBookmark(event: MouseEvent<HTMLButtonElement>) {
    stop(event);
    if (!user) {
      router.push("/login");
      return;
    }
    if (busy) return;
    const next = !bookmarked;
    setBookmarked(next);
    setBusy(true);
    try {
      await setPostBookmark(post.id, next);
      showToast(next ? "已收藏帖子" : "已取消收藏");
    } catch {
      setBookmarked(!next);
      showToast("收藏操作失败，请重试");
    } finally {
      setBusy(false);
    }
  }

  function handleCopyLink(event: MouseEvent) {
    stop(event);
    setMenuOpen(false);
    if (typeof window !== "undefined" && navigator.clipboard) {
      const url = `${window.location.origin}/post/${encodeURIComponent(post.id)}`;
      void navigator.clipboard.writeText(url);
      showToast("已复制帖子链接");
    }
  }

  function handleReport(event: MouseEvent) {
    stop(event);
    setMenuOpen(false);
    if (!user) {
      router.push(`/login?next=${encodeURIComponent(`/post/${post.id}`)}`);
      return;
    }
    setReportOpen(true);
  }

  async function handleDelete(event: MouseEvent) {
    stop(event);
    setMenuOpen(false);
    if (!window.confirm("确定要删除这条帖子吗？删除后将无法恢复。")) return;
    try {
      await deletePost(post.id);
      setDeleted(true);
      showToast("帖子已删除");
    } catch {
      showToast("删除帖子失败，请重试");
    }
  }

  const isAuthor = Boolean(user && user.id === post.author.id);

  return (
    <>
      <article className="post-card" data-post-id={post.id}>
        <div className="post-head">
          <Link
            href={`/user/${encodeURIComponent(post.author.id)}`}
            className="post-avatar"
            onClick={(e) => e.stopPropagation()}
            title={`查看 ${post.author.nickname} 的个人主页`}
          >
            <UserAvatar
              userId={post.author.id}
              name={post.author.nickname}
              url={post.author.avatarUrl}
              className="card-author-avatar"
            />
          </Link>
          <div className="post-author">
            <Link
              href={`/user/${encodeURIComponent(post.author.id)}`}
              className="author-line"
              onClick={(e) => e.stopPropagation()}
            >
              <span className="author-name">{post.author.nickname}</span>
              <span className="lv">Lv.{post.author.level || 1}</span>
            </Link>
            <div className="meta">
              {post.community.name} · {relativeTime(post.activityAt || post.createdAt)}
            </div>
          </div>

          <div className="post-card-more-wrapper">
            <button
              type="button"
              className="more"
              aria-label="更多操作"
              onClick={(e) => {
                stop(e);
                setMenuOpen((val) => !val);
              }}
            >
              <Icon name="more" size={16} />
            </button>
            {menuOpen && (
              <div className="post-card-menu-popover" onClick={(e) => stop(e)}>
                <button type="button" className="post-card-menu-item" onClick={handleCopyLink}>
                  <Icon name="copy" size={14} />
                  <span>复制链接</span>
                </button>
                <button
                  type="button"
                  className="post-card-menu-item"
                  onClick={(e) => {
                    setMenuOpen(false);
                    void handleBookmark(e);
                  }}
                >
                  <Icon name="bookmark" size={14} />
                  <span>{bookmarked ? "取消收藏" : "收藏帖子"}</span>
                </button>
                <button type="button" className="post-card-menu-item" onClick={handleReport}>
                  <Icon name="info" size={14} />
                  <span>举报帖子</span>
                </button>
                {isAuthor && (
                  <button
                    type="button"
                    className="post-card-menu-item danger"
                    onClick={handleDelete}
                  >
                    <Icon name="close" size={14} />
                    <span>删除帖子</span>
                  </button>
                )}
              </div>
            )}
          </div>
        </div>

        {(contextMeta || post.activityAt) && (
          <div className="reply-meta">
            <Icon name="message" size={13} />
            <span>{contextMeta || `最近回复 ${relativeTime(post.activityAt || post.createdAt)}`}</span>
          </div>
        )}

        <div className="post-card-body">
          <Link href={`/post/${encodeURIComponent(post.id)}`} className="post-card-content-link">
            <h2 className="post-title">{post.title}</h2>
            <p className="post-text">{post.content}</p>
          </Link>

          {post.media.length > 0 && (
            <div className={`post-media media-count-${Math.min(4, post.media.length)}`}>
              {post.media.slice(0, 4).map((item, index) => (
                <div
                  className="media-frame"
                  key={item.id || `${post.id}-${index}`}
                  style={{ cursor: "pointer" }}
                  onClick={(e) => {
                    stop(e);
                    setGalleryIndex(index);
                  }}
                >
                  <MediaImage
                    asset={item}
                    alt={item.altText || "帖子图片"}
                    loading={index === 0 ? "eager" : "lazy"}
                    className="media-image"
                  />
                  {post.media.length > 4 && index === 3 && (
                    <span className="media-more">+{post.media.length - 4}</span>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="post-actions">
          <div className="stats-left">
            <Link
              href={`/post/${encodeURIComponent(post.id)}#comments`}
              className="stat"
              aria-label={`回复 ${post.commentCount}`}
            >
              <Icon name="message" size={16} />
              <span>{compactCount(post.commentCount)}</span>
            </Link>
            <button
              type="button"
              className={`stat like-btn${liked ? " selected" : ""}`}
              onClick={handleLike}
              aria-label={liked ? "取消点赞" : "点赞"}
            >
              <Icon name="heart" size={16} />
              <span>{compactCount(likeCount)}</span>
            </button>
            <span className="stat" title={`浏览量 ${post.viewCount}`}>
              <Icon name="eye" size={16} />
              <span>{compactCount(post.viewCount)}</span>
            </span>
          </div>

          <button
            type="button"
            className={`bookmark${bookmarked ? " selected" : ""}`}
            onClick={handleBookmark}
            aria-label={bookmarked ? "取消收藏" : "收藏"}
          >
            <Icon name="bookmark" size={17} />
          </button>
        </div>
      </article>

      {galleryIndex !== null && (
        <ImageGalleryModal
          images={galleryImages}
          initialIndex={galleryIndex}
          onClose={() => setGalleryIndex(null)}
        />
      )}

      {reportOpen && (
        <ReportModal
          targetType="post"
          targetId={post.id}
          targetTitle={post.title}
          onClose={() => setReportOpen(false)}
        />
      )}
    </>
  );
}
