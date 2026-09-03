"use client";

import Link from "next/link";
import { MouseEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "./icons";
import { MediaImage } from "./media-image";
import { UserAvatar } from "./user-avatar";
import { useToast } from "./toast-context";
import type { Post, SessionUser } from "../types/forum";
import { setPostBookmark, setPostLike } from "../lib/api/forum";
import { compactCount, relativeTime } from "../lib/format";

function stop(event: MouseEvent) {
  event.preventDefault();
  event.stopPropagation();
}

function MediaGrid({ post }: { post: Post }) {
  if (!post.media.length) return null;
  const media = post.media.slice(0, 4);
  return (
    <div className={`post-media media-count-${media.length}`}>
      {media.map((item, index) => (
        <div className="media-frame" key={item.id || `${post.id}-${index}`}>
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
  );
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
    showToast(next ? "点赞成功" : "已取消点赞");
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
    setBusy(true);
    showToast(next ? "已收藏" : "已取消收藏");
    try {
      await setPostBookmark(post.id, next);
    } catch {
      setBookmarked(!next);
    } finally {
      setBusy(false);
    }
  }

  return (
    <article className="post-card" data-post-id={post.id}>
      <div className="post-head">
        <div className="post-avatar">
          <UserAvatar
            userId={post.author.id}
            name={post.author.nickname}
            url={post.author.avatarUrl}
            className="card-author-avatar"
          />
        </div>
        <div className="post-author">
          <div className="author-line">
            <span className="author-name">{post.author.nickname}</span>
            <span className="lv">Lv.{post.author.level || 1}</span>
          </div>
          <div className="meta">
            {post.community.name} · {relativeTime(post.activityAt || post.createdAt)}
          </div>
        </div>
        <button
          type="button"
          className="more"
          aria-label="更多"
          onClick={stop}
        >
          <Icon name="more" size={16} />
        </button>
      </div>

      {(contextMeta || post.activityAt) && (
        <div className="reply-meta">
          <Icon name="message" size={13} />
          <span>{contextMeta || `最近回复 ${relativeTime(post.activityAt || post.createdAt)}`}</span>
        </div>
      )}

      <Link href={`/post/${encodeURIComponent(post.id)}`} className="post-card-content-link">
        <h2 className="post-title">{post.title}</h2>
        <p className="post-text">{post.content}</p>
        <MediaGrid post={post} />
      </Link>

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
  );
}
