"use client";

import Link from "next/link";
import { MouseEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "./icons";
import type { Post, SessionUser } from "../types/forum";
import { setPostBookmark, setPostLike } from "../lib/api/forum";
import { compactCount, initials, relativeTime } from "../lib/format";

const avatarTones = ["blue", "lilac", "mint", "peach"];

function stop(event: MouseEvent) {
  event.preventDefault();
  event.stopPropagation();
}

function Avatar({ name, url, small = false }: { name: string; url?: string; small?: boolean }) {
  const tone = avatarTones[name.length % avatarTones.length];
  return (
    <span className={`avatar ${small ? "avatar-small" : ""} avatar-${tone}`}>
      {url ? <img src={url} alt="" /> : initials(name)}
    </span>
  );
}

function MediaGrid({ post }: { post: Post }) {
  if (!post.media.length) return null;
  const media = post.media.slice(0, 4);
  return (
    <div className={`post-media media-count-${media.length}`}>
      {media.map((item, index) => (
        <div className="media-frame" key={item.id || `${post.id}-${index}`}>
          <img src={item.thumbUrl || item.detailUrl || item.url} alt={item.altText || "帖子图片"} loading={index === 0 ? "eager" : "lazy"} />
          {post.media.length > 4 && index === 3 && <span className="media-more">+{post.media.length - 4}</span>}
        </div>
      ))}
    </div>
  );
}

export function PostCard({ post, user }: { post: Post; user: SessionUser | null }) {
  const router = useRouter();
  const [liked, setLiked] = useState(post.viewerState.hasLiked);
  const [bookmarked, setBookmarked] = useState(post.viewerState.hasBookmarked);
  const [likeCount, setLikeCount] = useState(post.likeCount);
  const [bookmarkCount, setBookmarkCount] = useState(post.bookmarkCount);
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

  return (
    <article className="post-card">
      <div className="post-card-head">
        <Avatar name={post.author.nickname} url={post.author.avatarUrl} />
        <div className="post-author-copy">
          <div className="post-author-name"><strong>{post.author.nickname}</strong><span className="level-label">Lv.{post.author.level || 1}</span></div>
          <div className="post-meta">{post.community.name} <span>·</span> {relativeTime(post.activityAt || post.createdAt)}</div>
        </div>
        <button type="button" className="more-button" aria-label="更多操作" onClick={stop}><Icon name="more" size={19} /></button>
      </div>
      <Link href={`/post/${encodeURIComponent(post.id)}`} className="post-card-link">
        <h3>{post.title}</h3>
        <p className="post-excerpt">{post.content}</p>
        <MediaGrid post={post} />
      </Link>
      <div className="post-actions">
        <div className="post-action-group">
          <Link href={`/post/${encodeURIComponent(post.id)}#comments`} className="post-action"><Icon name="message" size={18} /> <span>{compactCount(post.commentCount)}</span></Link>
          <button type="button" className={`post-action${liked ? " selected-like" : ""}`} onClick={handleLike} aria-label={liked ? "取消点赞" : "点赞"}><Icon name="heart" size={18} /> <span>{compactCount(likeCount)}</span></button>
          <span className="post-action post-views"><Icon name="eye" size={18} /> <span>{compactCount(post.viewCount)}</span></span>
        </div>
        <button type="button" className={`post-action bookmark-action${bookmarked ? " selected-bookmark" : ""}`} onClick={handleBookmark} aria-label={bookmarked ? "取消收藏" : "收藏"}>
          <Icon name="bookmark" size={18} /> <span>{bookmarkCount > 0 ? "收藏" : ""}</span>
        </button>
      </div>
    </article>
  );
}
