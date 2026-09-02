import { resolveAssetUrl } from "../config";
import type {
  AuthSession,
  Comment,
  Community,
  EmailCodeChallenge,
  FeedPage,
  MediaAsset,
  Post,
  ActivityItem,
  ForumNotification,
  SessionUser,
  ProfilePost,
  ProfileSummary,
  RankingToy,
  UserSummary,
} from "../../types/forum";
import { apiFetch, apiJson, apiPost, clearAccessToken, setAccessToken } from "./client";

type JsonRecord = Record<string, unknown>;

const asRecord = (value: unknown): JsonRecord =>
  value && typeof value === "object" ? (value as JsonRecord) : {};
const asString = (value: unknown, fallback = "") => (typeof value === "string" ? value : fallback);
const asNumber = (value: unknown, fallback = 0) =>
  typeof value === "number" ? value : Number.isFinite(Number(value)) ? Number(value) : fallback;
const asBoolean = (value: unknown, fallback = false) =>
  typeof value === "boolean" ? value : fallback;

function parseUser(raw: unknown): UserSummary {
  const item = asRecord(raw);
  const nickname = asString(item.nickname, asString(item.username, "杯友"));
  return {
    id: asString(item.id),
    username: asString(item.username, nickname),
    nickname,
    level: asNumber(item.level, 1),
    avatarUrl: resolveAssetUrl(asString(item.avatar_url, asString(item.avatar))),
  };
}

function parseCommunity(raw: unknown): Community {
  const item = asRecord(raw);
  return {
    id: asString(item.id),
    slug: asString(item.slug),
    name: asString(item.name, "未命名板块"),
    description: asString(item.description),
    memberCount: asNumber(item.member_count),
    followerCount: asNumber(item.follower_count),
    postCount: asNumber(item.post_count),
    sortOrder: asNumber(item.sort_order),
    canPublish: item.can_publish !== false,
  };
}

function parseMedia(raw: unknown): MediaAsset {
  const item = asRecord(raw);
  const thumb = asRecord(item.thumb);
  const detail = asRecord(item.detail);
  const original = asRecord(item.original);
  return {
    id: asString(item.id),
    type: item.type === "video" ? "video" : "image",
    url: resolveAssetUrl(asString(item.url)) || resolveAssetUrl(asString(detail.url)),
    thumbUrl: resolveAssetUrl(asString(thumb.url)),
    detailUrl: resolveAssetUrl(asString(detail.url)),
    originalUrl: resolveAssetUrl(asString(original.url)),
    width: asNumber(item.width, asNumber(detail.width)),
    height: asNumber(item.height, asNumber(detail.height)),
    altText: asString(item.alt_text, "社区图片"),
  };
}

export function parsePost(raw: unknown): Post {
  const item = asRecord(raw);
  const author = parseUser(item.author);
  const community = parseCommunity(item.community);
  const viewer = asRecord(item.viewer_state);
  return {
    id: asString(item.id),
    authorId: asString(author.id, asString(item.author_id)),
    communityId: asString(community.id, asString(item.community_id)),
    author,
    community,
    type: asString(item.type, "normal"),
    title: asString(item.title, "未命名帖子"),
    content: asString(item.content, asString(item.content_preview)),
    commentCount: asNumber(item.comment_count),
    likeCount: asNumber(item.like_count),
    bookmarkCount: asNumber(item.bookmark_count),
    shareCount: asNumber(item.share_count),
    viewCount: asNumber(item.view_count),
    createdAt: asString(item.created_at),
    updatedAt: asString(item.updated_at, asString(item.created_at)),
    publishedAt: asString(item.published_at) || undefined,
    activityAt: asString(item.activity_at) || undefined,
    media: Array.isArray(item.media) ? item.media.map(parseMedia) : [],
    viewerState: {
      hasLiked: asBoolean(viewer.has_liked),
      hasBookmarked: asBoolean(viewer.has_bookmarked),
      isFollowingAuthor: asBoolean(viewer.is_following_author),
      isFollowingCommunity: asBoolean(viewer.is_following_community),
      canEdit: asBoolean(viewer.can_edit),
      canDelete: asBoolean(viewer.can_delete),
      canReport: viewer.can_report !== false,
    },
  };
}

export function parseComment(raw: unknown): Comment {
  const item = asRecord(raw);
  const viewer = asRecord(item.viewer_state);
  return {
    id: asString(item.id),
    postId: asString(item.post_id),
    author: parseUser(item.author),
    content: asString(item.content),
    likeCount: asNumber(item.like_count),
    dislikeCount: asNumber(item.dislike_count),
    replyCount: asNumber(item.reply_count),
    floor: item.floor == null ? undefined : asNumber(item.floor),
    createdAt: asString(item.created_at),
    updatedAt: asString(item.updated_at, asString(item.created_at)),
    viewerState: {
      hasLiked: asBoolean(viewer.has_liked),
      hasDisliked: asBoolean(viewer.has_disliked),
    },
    replyPreview: Array.isArray(item.reply_preview) ? item.reply_preview.map(parseComment) : undefined,
  };
}

const uniqueNamedCommunities = (items: Community[]) => {
  const desired = new Set(["酱紫社区", "大型拆箱", "杂鱼日常"]);
  const seen = new Set<string>();
  return items
    .filter((item) => desired.has(item.name))
    .sort((a, b) => a.sortOrder - b.sortOrder || b.postCount - a.postCount)
    .filter((item) => {
      if (seen.has(item.name)) return false;
      seen.add(item.name);
      return true;
    });
};

export async function getCommunities(): Promise<Community[]> {
  const payload = await apiJson<{ items?: unknown[] }>("/communities");
  return uniqueNamedCommunities(Array.isArray(payload.items) ? payload.items.map(parseCommunity) : []);
}

export async function getFeed(options: {
  sort: "recommended" | "latest" | "featured" | "hot";
  communityId?: string;
  hasMedia?: boolean;
  limit?: number;
  cursor?: string;
}): Promise<FeedPage> {
  const params = new URLSearchParams({
    limit: String(options.limit ?? 20),
    sort: options.sort,
    latest_by: options.sort === "latest" ? "post" : "comment",
    include_details: "1",
  });
  if (options.communityId) params.set("community_id", options.communityId);
  if (options.hasMedia) params.set("has_media", "true");
  if (options.cursor) params.set("cursor", options.cursor);
  const payload = await apiJson<{ items?: unknown[]; next_cursor?: string; has_more?: boolean }>(
    `/feed/latest?${params.toString()}`,
  );
  return {
    items: Array.isArray(payload.items) ? payload.items.map(parsePost) : [],
    nextCursor: payload.next_cursor,
    hasMore: payload.has_more === true,
  };
}

export async function getActivities(): Promise<ActivityItem[]> {
  const payload = await apiJson<{ items?: unknown[] }>("/activities");
  return Array.isArray(payload.items)
    ? payload.items.map((raw) => {
        const item = asRecord(raw);
        const status = asString(item.status, asString(item.phase, "upcoming"));
        return {
          id: asString(item.id),
          title: asString(item.title, "未命名活动"),
          description: asString(item.description),
          coverUrl: resolveAssetUrl(asString(item.cover_url)),
          startAt: asString(item.start_at) || undefined,
          endAt: asString(item.end_at) || undefined,
          location: asString(item.location),
          status,
          phase: asString(item.phase) || undefined,
          authorName: asString(item.author_name, "社区官方"),
        } satisfies ActivityItem;
      })
    : [];
}

export async function getRankingToys(tab = ""): Promise<RankingToy[]> {
  const query = tab ? `?tab=${encodeURIComponent(tab)}` : "";
  const payload = await apiJson<{ items?: unknown[] }>(`/ranking/toys${query}`);
  return Array.isArray(payload.items)
    ? payload.items.map((raw, index) => {
        const item = asRecord(raw);
        const tags = Array.isArray(item.tags)
          ? item.tags.map((tag) => String(tag)).filter(Boolean)
          : [];
        return {
          id: asString(item.id),
          rank: asNumber(item.rank, index + 1),
          name: asString(item.name, "未命名产品"),
          merchant: asString(item.merchant),
          description: asString(item.description),
          tags,
          score: asNumber(item.score),
          wantCount: asNumber(item.want_count),
          ratingCount: asNumber(item.rating_count),
          coverUrl: resolveAssetUrl(asString(item.cover_url)),
          heroUrl: resolveAssetUrl(asString(item.hero_url)),
        } satisfies RankingToy;
      })
    : [];
}

export async function getPost(id: string): Promise<Post> {
  return parsePost(await apiJson<JsonRecord>(`/posts/${encodeURIComponent(id)}?include_details=1`));
}

export async function getComments(postId: string): Promise<Comment[]> {
  const payload = await apiJson<{ items?: unknown[] }>(
    `/posts/${encodeURIComponent(postId)}/comments?limit=30&offset=0&sort=asc`,
  );
  return Array.isArray(payload.items) ? payload.items.map(parseComment) : [];
}

export async function recordHistory(postId: string): Promise<void> {
  await apiPost(`/posts/${encodeURIComponent(postId)}/history`);
}

export async function setPostLike(postId: string, active: boolean): Promise<void> {
  await apiFetch(`/posts/${encodeURIComponent(postId)}/like`, { method: active ? "PUT" : "DELETE" });
}

export async function setPostBookmark(postId: string, active: boolean): Promise<void> {
  await apiFetch(`/posts/${encodeURIComponent(postId)}/bookmark`, { method: active ? "PUT" : "DELETE" });
}

export async function setCommentLike(commentId: string, active: boolean): Promise<void> {
  await apiFetch(`/comments/${encodeURIComponent(commentId)}/like`, {
    method: active ? "PUT" : "DELETE",
  });
}

export async function createComment(postId: string, content: string): Promise<Comment> {
  const idempotencyKey =
    typeof crypto !== "undefined" && "randomUUID" in crypto
      ? crypto.randomUUID()
      : `web-comment-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return parseComment(
    await apiPost(`/posts/${encodeURIComponent(postId)}/comments`, { content }, {
      "Idempotency-Key": idempotencyKey,
    }),
  );
}

export async function createPost(communityId: string, title: string, content: string): Promise<Post> {
  const idempotencyKey =
    typeof crypto !== "undefined" && "randomUUID" in crypto
      ? crypto.randomUUID()
      : `web-post-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return parsePost(
    await apiPost(
      "/posts",
      { community_id: communityId, type: "normal", title, content },
      { "Idempotency-Key": idempotencyKey },
    ),
  );
}

export async function requestEmailCode(email: string): Promise<EmailCodeChallenge> {
  const payload = await apiPost<JsonRecord>("/auth/email/request", { email, scene: "login" });
  return {
    expiresIn: asNumber(payload.expires_in, 600),
    retryAfter: asNumber(payload.retry_after, 60),
    delivery: asString(payload.delivery, "email"),
    devCode: asString(payload.dev_code) || undefined,
  };
}

function parseSession(payload: JsonRecord): AuthSession {
  const token = asString(payload.access_token);
  if (!token) throw new Error("登录响应格式错误");
  setAccessToken(token);
  return {
    accessToken: token,
    expiresIn: asNumber(payload.expires_in) || undefined,
    user: parseUser(payload.user) as SessionUser,
  };
}

export async function loginWithEmailCode(email: string, code: string): Promise<AuthSession> {
  return parseSession(await apiPost<JsonRecord>("/auth/email/verify", { email, code }));
}

export async function loginAsGuest(): Promise<AuthSession> {
  return parseSession(await apiPost<JsonRecord>("/auth/guest"));
}

export async function getMe(): Promise<SessionUser> {
  return parseUser(await apiJson<JsonRecord>("/me")) as SessionUser;
}

export async function getUserProfile(id: string): Promise<ProfileSummary> {
  const item = asRecord(await apiJson<JsonRecord>(`/users/${encodeURIComponent(id)}`));
  const viewer = asRecord(item.viewer_state);
  const user = parseUser(item);
  return {
    ...user,
    bio: asString(item.bio, asString(item.signature, "")),
    experience: asNumber(item.experience),
    postCount: asNumber(item.post_count),
    commentCount: asNumber(item.comment_count),
    likeReceivedCount: asNumber(item.like_received_count),
    followerCount: asNumber(item.follower_count),
    followingCount: asNumber(item.following_count),
    publicId: asString(item.public_id) || undefined,
    createdAt: asString(item.created_at) || undefined,
    isFollowing: asBoolean(viewer.is_following),
    canFollow: asBoolean(viewer.can_follow),
  };
}

export async function getUserPosts(id: string): Promise<ProfilePost[]> {
  const payload = await apiJson<{ items?: unknown[] }>(`/users/${encodeURIComponent(id)}/posts?limit=20`);
  return Array.isArray(payload.items)
    ? payload.items.map((raw) => {
        const item = asRecord(raw);
        return {
          id: asString(item.id),
          title: asString(item.title, "未命名帖子"),
          contentPreview: asString(item.content_preview, asString(item.content)),
          communityName: asString(item.community_name, "社区"),
          commentCount: asNumber(item.comment_count),
          likeCount: asNumber(item.like_count),
          viewCount: asNumber(item.view_count),
          createdAt: asString(item.created_at, asString(item.published_at)),
        } satisfies ProfilePost;
      })
    : [];
}

export async function setUserFollow(id: string, active: boolean): Promise<void> {
  await apiFetch(`/users/${encodeURIComponent(id)}/follow`, { method: active ? "PUT" : "DELETE" });
}

export async function getNotifications(options: {
  category?: string;
  cursor?: string;
  limit?: number;
} = {}): Promise<{ items: ForumNotification[]; nextCursor?: string; hasMore: boolean }> {
  const params = new URLSearchParams({ limit: String(options.limit ?? 30) });
  if (options.category) params.set("category", options.category);
  if (options.cursor) params.set("cursor", options.cursor);
  const payload = await apiJson<{ items?: unknown[]; next_cursor?: string; has_more?: boolean }>(`/notifications?${params.toString()}`);
  return {
    items: Array.isArray(payload.items)
      ? payload.items.map((raw) => {
          const item = asRecord(raw);
          return {
            id: asString(item.id),
            type: asString(item.type),
            actor: parseUser(item.actor),
            targetType: asString(item.target_type),
            targetId: asString(item.target_id),
            targetData: asRecord(item.target_data),
            isRead: asBoolean(item.is_read),
            createdAt: asString(item.created_at),
          } satisfies ForumNotification;
        })
      : [],
    nextCursor: asString(payload.next_cursor) || undefined,
    hasMore: payload.has_more === true,
  };
}

export async function getUnreadNotificationCount(): Promise<number> {
  const payload = await apiJson<JsonRecord>("/notifications/unread-count");
  return asNumber(payload.unread_count);
}

export async function markAllNotificationsRead(): Promise<void> {
  await apiPost("/notifications/read-all", {});
}

export async function markNotificationRead(id: string): Promise<void> {
  await apiFetch(`/notifications/${encodeURIComponent(id)}/read`, { method: "PATCH" });
}

export async function logout(): Promise<void> {
  try {
    await apiPost("/auth/logout", {});
  } finally {
    clearAccessToken();
  }
}
