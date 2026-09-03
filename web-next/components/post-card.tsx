"use client";

import Link from "next/link";
import { MouseEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "./icons";
import { MediaImage } from "./media-image";
import { UserAvatar } from "./user-avatar";
import type { Post, SessionUser } from "../types/forum";
import { setPostBookmark, setPostLike } from "../lib/api/forum";
import { compactCount, relativeTime } from "../lib/format";

function stop(event: MouseEvent) {
  event.preventDefault();
  event.stopPropagation();
}

const communityToneMap: Record<string, string> = {
  酱紫社区: "lilac",
  大型拆箱: "orange",
  杂鱼日常: "mint",
};

function MediaGrid({ post }: { post: Post }) {
  if (!post.media.length) return null;
  const media = post.media.slice(0, 4);
  return (
    <div className={`post-media media-count-${media.length}`}>
      {media.map((item, index) => (
        <div className="media-frame" key={item.id || `${post.id}-${index}`}>
          <MediaImage asset={item} alt={item.altText || "帖子图片"} loading={index === 0 ? "eager" : "lazy"} className="media-image" />
          {post.media.length > 4 && index === 3 && <span className="media-more">+{post.media.length - 4}</span>}
        </div>
      ))}
    </div>
  );
}

export function PostCard({ post, user, contextMeta }: { post: Post; user: SessionUser | null; contextMeta?: string }) {
  const router = useRouter();
  const [liked, setLiked] = useState(post.viewerState.hasLiked);
  const [bookmarked, setBookmarked] = useState(post.viewerState.hasBookmarked);
  const [likeCount, setLikeCount] = useState(post.likeCount);
  const [bookmarkCount, setBookmarkCount] = useState(post.bookmarkCount);
  const [busy, setBusy] = useState(false);

  const tone = communityToneMap[post.community.name] || "blue";

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
    setBookmarkCount((value) => Math.max(0, value + (next ? 1 : -1)));
    setBusy(true);
    try {
      await setPostBookmark(post.id, next);
    } catch {
      setBookmarked(!next);
      setBookmarkCount((value) => Math.max(0, value + (next ? -1 : 1)));
    } finally {
      setBusy(false);
    }
  }

  const postNumber = post.id.replace(/\D/g, "").slice(-4) || post.id.slice(-4);

  return (
    <article className="post-card">
      <div className="post-card-head">
        <UserAvatar userId={post.author.id} name={post.author.nickname} url={post.author.avatarUrl} className="post-author-avatar" />
        <div className="post-author-copy">
          <div className="post-author-name">
            <strong>{post.author.nickname}</strong>
            <span className="level-label">Lv.{post.author.level || 1}</span>
            <span className={`post-community-pill tone-${tone}`}>{post.community.name}</span>
          </div>
          <div className="post-meta">
            <span>{relativeTime(post.activityAt || post.createdAt)}</span>
            {postNumber && (
              <>
                <span className="meta-separator">·</span>
                <span className="post-floor">#{postNumber}</span>
              </>
            )}
          </div>
        </div>
        <button type="button" className="more-button" aria-label="更多操作" onClick={stop}>
          <Icon name="more" size={18} />
        </button>
      </div>

      {post.isFeatured && (
        <div className="post-badges">
          <span className="post-badge featured">精华</span>
        </div>
      )}

      <Link href={`/post/${encodeURIComponent(post.id)}`} className="post-card-link">
        {contextMeta && (
          <div className="post-context-meta">
            <Icon name="message" size={13} />
            <span>{contextMeta}</span>
          </div>
        )}
        <h3 className="post-title">{post.title}</h3>
        <p className="post-excerpt">{post.content}</p>
        <MediaGrid post={post} />
      </Link>

      <div className="post-actions">
        <div className="post-action-group">
          <Link href={`/post/${encodeURIComponent(post.id)}#comments`} className="post-action">
            <Icon name="message" size={17} />
            <span>{compactCount(post.commentCount)}</span>
          </Link>
          <button
            type="button"
            className={`post-action like-button${liked ? " selected-like" : ""}`}
            onClick={handleLike}
            aria-label={liked ? "取消点赞" : "点赞"}
          >
            <Icon name="heart" size={17} />
            <span>{compactCount(likeCount)}</span>
          </button>
          <span className="post-action post-views" title={`浏览量 ${post.viewCount}`}>
            <Icon name="eye" size={17} />
            <span>{compactCount(post.viewCount)}</span>
          </span>
        </div>

        <div className="post-actions-right">
          <button
            type="button"
            className={`post-action bookmark-action${bookmarked ? " selected-bookmark" : ""}`}
            onClick={handleBookmark}
            aria-label={bookmarked ? "取消收藏" : "收藏"}
          >
            <Icon name="bookmark" size={17} />
            <span>{bookmarkCount > 0 ? compactCount(bookmarkCount) : ""}</span>
          </button>
          <Link href={`/post/${encodeURIComponent(post.id)}`} className="post-view-discussion">
            <span>查看讨论</span>
            <Icon name="chevron-right" size={14} />
          </Link>
        </div>
      </div>
    </article>
  );
}
