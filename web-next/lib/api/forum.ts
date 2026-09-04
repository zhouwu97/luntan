import { resolveMediaUrl } from "../media-url";
import type {
  ActivityItem,
  AuthSession,
  Comment,
  CommentContext,
  CommentPage,
  Community,
  EmailCodeChallenge,
  FeedPage,
  ForumNotification,
  MediaAsset,
  Post,
  ProfilePost,
  ProfilePostPage,
  ProfileSummary,
  RankingAdminView,
  RankingAdminViewItem,
  RankingToy,
  RankingToyComment,
  RankingToyCommentPage,
  RankingToyDetail,
  ReportInput,
  ReportResult,
  SearchResults,
  SessionUser,
  UserSummary,
} from "../../types/forum";
import { apiFetch, apiJson, apiPost, clearAccessToken, setAccessToken } from "./client";

type JsonRecord = Record<string, unknown>;

const asRecord = (value: unknown): JsonRecord =>
  value && typeof value === "object" ? (value as JsonRecord) : {};
const asString = (value: unknown, fallback = "") => (typeof value === "string" ? value : fallback);
const asNumber = (value: unknown, fallback = 0) =>
  typeof value === "number" && !Number.isNaN(value) ? value : fallback;
const asBoolean = (value: unknown, fallback = false) =>
  typeof value === "boolean" ? value : fallback;

function parseCapabilities(raw: unknown): Record<string, boolean> | undefined {
  const item = asRecord(raw);
  const entries = Object.entries(item)
    .filter(([, value]) => typeof value === "boolean")
    .map(([key, value]) => [key, value as boolean] as const);
  return entries.length ? Object.fromEntries(entries) : undefined;
}

function parseUser(raw: unknown): UserSummary {
  const item = asRecord(raw);
  const nickname = asString(item.nickname, asString(item.username, "杯友"));
  return {
    id: asString(item.id),
    username: asString(item.username, nickname),
    nickname,
    level: asNumber(item.level, 1),
    avatarUrl: resolveMediaUrl(asString(item.avatar_url, asString(item.avatar)), "original"),
  };
}

function parseSessionUser(raw: unknown): SessionUser {
  const item = asRecord(raw);
  return {
    ...parseUser(item),
    accountType: asString(item.account_type) || undefined,
    experience: asNumber(item.experience),
    email: asString(item.email) || undefined,
    status: asString(item.status) || undefined,
    role: asString(item.role) || undefined,
    capabilities: parseCapabilities(item.capabilities),
  };
}

function parseCommunity(raw: unknown): Community {
  const item = asRecord(raw);
  const viewer = asRecord(item.viewer_state);
  return {
    id: asString(item.id),
    slug: asString(item.slug),
    name: asString(item.name, "未命名板块"),
    description: asString(item.description),
    status: asString(item.status) || undefined,
    memberCount: asNumber(item.member_count),
    followerCount: asNumber(item.follower_count),
    postCount: asNumber(item.post_count),
    sortOrder: asNumber(item.sort_order),
    canPublish: asBoolean(item.can_publish),
    canUploadMedia: asBoolean(item.can_upload_media),
    canCreatePoll: asBoolean(item.can_create_poll),
    isFollowing: asBoolean(viewer.is_following),
    isMember: asBoolean(viewer.is_member),
  };
}

function parseMedia(raw: unknown): MediaAsset {
  if (typeof raw === "string" && raw.trim()) {
    const rawUrl = raw.trim();
    const url = resolveMediaUrl(rawUrl, "original") || rawUrl;
    return {
      id: rawUrl,
      type: "image",
      url,
      thumbUrl: resolveMediaUrl(rawUrl, "thumb") || url,
      detailUrl: resolveMediaUrl(rawUrl, "detail") || url,
      originalUrl: url,
      altText: "社区图片",
    };
  }
  const item = asRecord(raw);
  const thumb = asRecord(item.thumb);
  const detail = asRecord(item.detail);
  const original = asRecord(item.original);
  const rawUrl = asString(item.url) || asString(detail.url) || asString(original.url) || asString(thumb.url);
  const resolvedUrl = resolveMediaUrl(rawUrl) || rawUrl;
  return {
    id: asString(item.id, rawUrl),
    type: item.type === "video" ? "video" : "image",
    url: resolvedUrl,
    thumbUrl: resolveMediaUrl(asString(thumb.url), "thumb") || resolvedUrl,
    detailUrl: resolveMediaUrl(asString(detail.url), "detail") || resolvedUrl,
    originalUrl: resolveMediaUrl(asString(original.url), "original") || resolvedUrl,
    width: asNumber(item.width, asNumber(detail.width)),
    height: asNumber(item.height, asNumber(detail.height)),
    altText: asString(item.alt_text, "社区图片"),
  };
}

function parseMediaList(rawRecord: JsonRecord): MediaAsset[] {
  const rawList = Array.isArray(rawRecord.media)
    ? rawRecord.media
    : Array.isArray(rawRecord.images)
      ? rawRecord.images
      : [];
  return rawList.map(parseMedia);
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
    media: parseMediaList(item),
    isFeatured: item.is_featured === true,
    isRecommended: item.is_recommended === true,
    recommendationPosition: item.recommendation_position == null ? undefined : asNumber(item.recommendation_position),
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
    media: parseMediaList(item),
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

function parseRankingToy(raw: unknown, index = 0): RankingToy {
  const item = asRecord(raw);
  const viewer = asRecord(item.viewer_state);
  return {
    id: asString(item.id),
    rank: asNumber(item.rank, index + 1),
    sourceRank: item.source_rank == null ? undefined : asNumber(item.source_rank),
    name: asString(item.name, "未命名产品"),
    merchant: asString(item.merchant),
    description: asString(item.description),
    tags: Array.isArray(item.tags) ? item.tags.map(String).filter(Boolean) : [],
    score: asNumber(item.score),
    wantCount: asNumber(item.want_count),
    ratingCount: asNumber(item.rating_count),
    coverUrl: resolveMediaUrl(asString(item.cover_url), "detail"),
    heroUrl: resolveMediaUrl(asString(item.hero_url), "detail"),
    category: asString(item.category) || undefined,
    segments: Array.isArray(item.segments) ? item.segments.map(String).filter(Boolean) : undefined,
    releaseYear: item.release_year == null ? undefined : asNumber(item.release_year),
    couponUrl: asString(item.coupon_url) || undefined,
    sourceUrl: asString(item.source_url) || undefined,
    viewerState: Object.keys(viewer).length
      ? {
          wanted: asBoolean(viewer.wanted),
          owned: asBoolean(viewer.owned),
          rating: viewer.rating == null ? undefined : asNumber(viewer.rating),
        }
      : undefined,
  };
}

function parseRankingToyComment(raw: unknown): RankingToyComment {
  const item = asRecord(raw);
  const viewer = asRecord(item.viewer_state);
  const author = parseUser(item.author);
  const replyToUser = item.reply_to_user && typeof item.reply_to_user === "object"
    ? parseUser(item.reply_to_user)
    : undefined;
  return {
    id: asString(item.id),
    author,
    content: asString(item.content),
    likeCount: asNumber(item.like_count),
    replyCount: asNumber(item.reply_count),
    rootId: asString(item.root_id) || undefined,
    parentId: asString(item.parent_id) || undefined,
    replyToUserId: asString(item.reply_to_user_id) || undefined,
    replyToUser,
    createdAt: asString(item.created_at),
    rating: item.author_rating == null ? undefined : asNumber(item.author_rating),
    media: Array.isArray(item.media) ? item.media.map(parseMedia) : [],
    viewerState: { hasLiked: asBoolean(viewer.has_liked) },
    replyPreview: Array.isArray(item.reply_preview)
      ? item.reply_preview.map(parseRankingToyComment)
      : [],
  };
}

function parseRankingToyDetail(raw: unknown): RankingToyDetail {
  const item = asRecord(raw);
  const toy = parseRankingToy(item);
  const rawDistribution = asRecord(item.rating_distribution);
  return {
    ...toy,
    releaseYear: asNumber(item.release_year),
    ratingDistribution: Object.fromEntries(Object.entries(rawDistribution).map(([key, value]) => [key, asNumber(value)])),
    comments: Array.isArray(item.comments) ? item.comments.map(parseRankingToyComment) : [],
    commentsNextCursor: asString(item.comments_next_cursor) || undefined,
    commentsHasMore: asBoolean(item.comments_has_more),
    commentSort: asString(item.comment_sort, "weight"),
  };
}

export async function getCommunities(options: { canPublish?: boolean; status?: string } = {}): Promise<Community[]> {
  const params = new URLSearchParams();
  if (options.canPublish) params.set("can_publish", "true");
  if (options.status) params.set("status", options.status);
  const query = params.size ? `?${params.toString()}` : "";
  const payload = await apiJson<{ items?: unknown[] }>(`/communities${query}`);
  const seen = new Set<string>();
  return (Array.isArray(payload.items) ? payload.items.map(parseCommunity) : [])
    .sort((a, b) => a.sortOrder - b.sortOrder || b.postCount - a.postCount)
    .filter((item) => {
      if (!item.id || seen.has(item.id)) return false;
      seen.add(item.id);
      return true;
    });
}

export async function getCommunity(id: string): Promise<Community> {
  return parseCommunity(await apiJson<JsonRecord>(`/communities/${encodeURIComponent(id)}`));
}

export async function getFeed(options: {
  sort: "recommended" | "latest" | "hot";
  communityId?: string;
  hasMedia?: boolean;
  latestOrder?: "comment" | "post";
  topic?: string;
  limit?: number;
  cursor?: string;
}): Promise<FeedPage> {
  const params = new URLSearchParams({
    limit: String(options.limit ?? 20),
    sort: options.sort,
    latest_by: options.latestOrder ?? "comment",
    include_details: "1",
  });
  if (options.communityId) params.set("community_id", options.communityId);
  if (options.hasMedia) params.set("has_media", "true");
  if (options.topic) params.set("topic", options.topic);
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
          coverUrl: resolveMediaUrl(asString(item.cover_url), "detail"),
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

export async function getRankingToys(tab = "", category = ""): Promise<RankingToy[]> {
  const params = new URLSearchParams();
  if (tab) params.set("tab", tab);
  if (category) params.set("category", category);
  const query = params.size ? `?${params.toString()}` : "";
  const payload = await apiJson<{ items?: unknown[] }>(`/ranking/toys${query}`);
  return Array.isArray(payload.items) ? payload.items.map(parseRankingToy) : [];
}

export async function getRankingView(tab = "", category = ""): Promise<{ items: RankingToy[]; weeklyTop?: RankingToy }> {
  const params = new URLSearchParams();
  if (tab) params.set("tab", tab);
  if (category) params.set("category", category);
  const query = params.size ? `?${params.toString()}` : "";
  const payload = await apiJson<{ items?: unknown[]; weekly_top?: unknown }>(`/ranking/toys${query}`);
  return {
    items: Array.isArray(payload.items) ? payload.items.map(parseRankingToy) : [],
    weeklyTop: payload.weekly_top ? parseRankingToy(payload.weekly_top) : undefined,
  };
}

export async function getRankingToy(id: string): Promise<RankingToy> {
  return parseRankingToy(await apiJson<JsonRecord>(`/ranking/toys/${encodeURIComponent(id)}`));
}

export async function getRankingToyDetail(id: string, sort: "weight" | "latest" = "weight"): Promise<RankingToyDetail> {
  return parseRankingToyDetail(await apiJson<JsonRecord>(`/ranking/toys/${encodeURIComponent(id)}?comment_sort=${sort}`));
}

export async function getRankingToyComments(
  toyId: string,
  sort: "weight" | "latest" = "weight",
  cursor?: string,
  limit = 20,
): Promise<RankingToyCommentPage> {
  const params = new URLSearchParams({ sort, limit: String(limit) });
  if (cursor) params.set("cursor", cursor);
  const payload = await apiJson<{ items?: unknown[]; next_cursor?: string; has_more?: boolean }>(
    `/ranking/toys/${encodeURIComponent(toyId)}/comments?${params.toString()}`,
  );
  return {
    items: Array.isArray(payload.items) ? payload.items.map(parseRankingToyComment) : [],
    nextCursor: asString(payload.next_cursor) || undefined,
    hasMore: payload.has_more === true,
  };
}

export async function getRankingToyCommentReplies(
  commentId: string,
  cursor?: string,
  limit = 20,
): Promise<RankingToyCommentPage> {
  const params = new URLSearchParams({ limit: String(limit) });
  if (cursor) params.set("cursor", cursor);
  const payload = await apiJson<{ items?: unknown[]; next_cursor?: string; has_more?: boolean }>(
    `/ranking/toy-comments/${encodeURIComponent(commentId)}/replies?${params.toString()}`,
  );
  return {
    items: Array.isArray(payload.items) ? payload.items.map(parseRankingToyComment) : [],
    nextCursor: asString(payload.next_cursor) || undefined,
    hasMore: payload.has_more === true,
  };
}

export async function setRankingToyWant(id: string, active: boolean): Promise<void> {
  await apiFetch(`/ranking/toys/${encodeURIComponent(id)}/want`, { method: active ? "PUT" : "DELETE" });
}

export async function setRankingToyOwned(id: string, active: boolean): Promise<void> {
  await apiFetch(`/ranking/toys/${encodeURIComponent(id)}/owned`, { method: active ? "PUT" : "DELETE" });
}

export async function rateRankingToy(id: string, score: number): Promise<RankingToy> {
  return parseRankingToy(await apiPost(`/ranking/toys/${encodeURIComponent(id)}/rating`, { score }));
}

export async function createRankingToyComment(
  toyId: string,
  content: string,
  parentId?: string,
  replyToUserId?: string,
): Promise<RankingToyComment> {
  return parseRankingToyComment(await apiPost(`/ranking/toys/${encodeURIComponent(toyId)}/comments`, {
    content,
    ...(parentId ? { parent_id: parentId } : {}),
    ...(replyToUserId ? { reply_to_user_id: replyToUserId } : {}),
  }, { "Idempotency-Key": newIdempotencyKey("web-toy-comment") }));
}

export async function setRankingToyCommentLike(
  commentId: string,
  active: boolean,
): Promise<{ active: boolean; likeCount: number }> {
  const payload = await apiJson<JsonRecord>(
    `/ranking/toy-comments/${encodeURIComponent(commentId)}/like`,
    { method: active ? "PUT" : "DELETE" },
  );
  return { active, likeCount: asNumber(payload.like_count) };
}

export async function deleteRankingToyComment(commentId: string): Promise<void> {
  await apiFetch(`/ranking/toy-comments/${encodeURIComponent(commentId)}`, { method: "DELETE" });
}

export async function submitRankingToy(input: {
  name: string;
  category: string;
  merchant?: string;
  releaseYear?: number;
  description?: string;
  coverMediaId?: string;
  intensity?: string;
  tags?: string[];
}): Promise<{ id: string; status: string }> {
  const payload = await apiPost<JsonRecord>("/ranking/submissions", {
    name: input.name,
    category: input.category,
    ...(input.merchant ? { merchant: input.merchant } : {}),
    ...(input.releaseYear ? { release_year: input.releaseYear } : {}),
    ...(input.description ? { description: input.description } : {}),
    ...(input.coverMediaId ? { cover_media_id: input.coverMediaId } : {}),
    ...(input.intensity ? { intensity: input.intensity } : {}),
    ...(input.tags?.length ? { tags: input.tags } : {}),
  });
  return { id: asString(payload.id), status: asString(payload.status, "pending") };
}

export async function getPost(id: string): Promise<Post> {
  return parsePost(await apiJson<JsonRecord>(`/posts/${encodeURIComponent(id)}?include_details=1`));
}

export async function getComments(
  postId: string,
  options: { offset?: number; limit?: number; sort?: "asc" | "desc" | "hot"; authorId?: string } = {},
): Promise<CommentPage> {
  const params = new URLSearchParams({
    limit: String(options.limit ?? 30),
    offset: String(options.offset ?? 0),
    sort: options.sort || "asc",
  });
  if (options.authorId) params.set("author_id", options.authorId);
  const payload = await apiJson<{ items?: unknown[]; total?: number; has_more?: boolean }>(
    `/posts/${encodeURIComponent(postId)}/comments?${params.toString()}`,
  );
  const items = Array.isArray(payload.items) ? payload.items.map(parseComment) : [];
  const total = typeof payload.total === "number" ? payload.total : items.length;
  const hasMore = payload.has_more === true || total > (options.offset ?? 0) + items.length;
  return { items, total, hasMore };
}

export async function getCommentReplies(
  commentId: string,
  cursor?: string,
): Promise<{ items: Comment[]; nextCursor?: string; hasMore: boolean }> {
  const params = new URLSearchParams({ limit: "30" });
  if (cursor) params.set("cursor", cursor);
  const payload = await apiJson<{ items?: unknown[]; next_cursor?: string; has_more?: boolean }>(
    `/comments/${encodeURIComponent(commentId)}/replies?${params.toString()}`,
  );
  return {
    items: Array.isArray(payload.items) ? payload.items.map(parseComment) : [],
    nextCursor: asString(payload.next_cursor) || undefined,
    hasMore: payload.has_more === true,
  };
}

export async function getCommentContext(commentId: string): Promise<CommentContext> {
  const payload = await apiJson<JsonRecord>(
    `/comments/${encodeURIComponent(commentId)}/context`,
  );
  return {
    postId: asString(payload.post_id),
    commentId: asString(payload.comment_id),
    rootId: asString(payload.root_id),
    parentId: asString(payload.parent_id) || undefined,
    isRoot: payload.is_root === true,
    rootComment: payload.root_comment ? parseComment(payload.root_comment) : undefined,
    targetComment: payload.target_comment ? parseComment(payload.target_comment) : undefined,
  };
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

export async function setCommentDislike(commentId: string, active: boolean): Promise<void> {
  await apiFetch(`/comments/${encodeURIComponent(commentId)}/dislike`, {
    method: active ? "PUT" : "DELETE",
  });
}

export async function deletePost(postId: string): Promise<void> {
  await apiFetch(`/posts/${encodeURIComponent(postId)}`, { method: "DELETE" });
}

export async function deleteComment(commentId: string): Promise<void> {
  await apiFetch(`/comments/${encodeURIComponent(commentId)}`, { method: "DELETE" });
}

function newIdempotencyKey(prefix: string): string {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export async function createComment(postId: string, content: string, mediaIds?: string[]): Promise<Comment> {
  return parseComment(
    await apiPost(
      `/posts/${encodeURIComponent(postId)}/comments`,
      {
        content,
        ...(mediaIds && mediaIds.length > 0 ? { media_ids: mediaIds } : {}),
      },
      {
        "Idempotency-Key": newIdempotencyKey("web-comment"),
      },
    ),
  );
}

export async function createReply(
  commentId: string,
  content: string,
  replyToUserId?: string,
  mediaIds?: string[],
): Promise<Comment> {
  return parseComment(
    await apiPost(
      `/comments/${encodeURIComponent(commentId)}/replies`,
      {
        content,
        reply_to_user_id: replyToUserId || undefined,
        ...(mediaIds && mediaIds.length > 0 ? { media_ids: mediaIds } : {}),
      },
      {
        "Idempotency-Key": newIdempotencyKey("web-reply"),
      },
    ),
  );
}

export async function createPost(
  communityId: string,
  title: string,
  content: string,
  mediaIds: string[] = [],
): Promise<Post> {
  const result = await apiPost<JsonRecord>(
    "/posts",
    { community_id: communityId, type: "normal", title, content, media_ids: mediaIds },
    { "Idempotency-Key": newIdempotencyKey("web-post") },
  );
  const id = asString(result.id);
  if (!id) throw new Error("发布成功，但后端没有返回帖子 ID");
  return getPost(id);
}

async function imageDimensions(file: File): Promise<{ width: number; height: number }> {
  if (typeof createImageBitmap === "function") {
    const bitmap = await createImageBitmap(file);
    try {
      return { width: bitmap.width, height: bitmap.height };
    } finally {
      bitmap.close();
    }
  }
  return new Promise((resolve, reject) => {
    const image = new Image();
    const url = URL.createObjectURL(file);
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve({ width: image.naturalWidth, height: image.naturalHeight });
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("无法读取图片尺寸"));
    };
    image.src = url;
  });
}

async function sha256(file: File): Promise<string> {
  const bytes = await file.arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join("");
}

export async function uploadImage(file: File): Promise<string> {
  if (!file.type.startsWith("image/")) throw new Error("只能上传图片文件");
  const [{ width, height }, hash] = await Promise.all([imageDimensions(file), sha256(file)]);
  const token = await apiPost<JsonRecord>("/media/upload-token", {
    file_name: file.name,
    mime_type: file.type,
    width,
    height,
    size: file.size,
    sha256: hash,
  });
  const mediaId = asString(token.media_id);
  const uploadUrl = asString(token.upload_url);
  const uploadMethod = asString(token.upload_method, "PUT");
  if (!mediaId || !uploadUrl) throw new Error("媒体上传凭证格式错误");

  const target = /^https?:\/\//i.test(uploadUrl)
    ? uploadUrl
    : new URL(uploadUrl, window.location.origin).toString();
  const uploadResponse = await fetch(target, {
    method: uploadMethod,
    body: file,
    headers: file.type ? { "Content-Type": file.type } : undefined,
  });
  if (!uploadResponse.ok) throw new Error(`图片上传失败（HTTP ${uploadResponse.status}）`);

  await apiPost(`/media/${encodeURIComponent(mediaId)}/complete`, {
    size: file.size,
    sha256: hash,
  });
  return mediaId;
}

export async function requestEmailCode(email: string, scene: "login" | "register" = "login"): Promise<EmailCodeChallenge> {
  const payload = await apiPost<JsonRecord>("/auth/email/request", { email, scene });
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
    user: parseSessionUser(payload.user),
  };
}

export async function loginWithEmailCode(email: string, code: string): Promise<AuthSession> {
  return parseSession(await apiPost<JsonRecord>("/auth/email/verify", { email, code }));
}

export async function loginWithPassword(email: string, password: string): Promise<AuthSession> {
  return parseSession(await apiPost<JsonRecord>("/auth/login/password", { email, password }));
}

export async function registerWithEmail(
  email: string,
  password: string,
  code?: string,
  nickname = "",
): Promise<AuthSession> {
  return parseSession(
    await apiPost<JsonRecord>("/auth/register", {
      email,
      ...(code && code.trim() ? { code: code.trim() } : {}),
      password,
      nickname,
    }),
  );
}

export async function loginAsGuest(): Promise<AuthSession> {
  return parseSession(await apiPost<JsonRecord>("/auth/guest"));
}

export async function getMe(): Promise<SessionUser> {
  return parseSessionUser(await apiJson<JsonRecord>("/me"));
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

function parseProfilePost(raw: unknown): ProfilePost {
  const item = asRecord(raw);
  return {
    id: asString(item.id),
    commentId: asString(item.comment_id) || undefined,
    activityAt: asString(item.activity_at) || undefined,
    title: asString(item.title, "未命名帖子"),
    contentPreview: asString(item.content_preview, asString(item.content)),
    communityName: asString(item.community_name, "社区"),
    commentCount: asNumber(item.comment_count),
    likeCount: asNumber(item.like_count),
    viewCount: asNumber(item.view_count),
    createdAt: asString(item.created_at, asString(item.published_at)),
  } satisfies ProfilePost;
}

export async function getUserPosts(
  id: string,
  cursor?: string,
  limit = 20,
): Promise<ProfilePostPage> {
  const params = new URLSearchParams({ limit: String(limit) });
  if (cursor) params.set("cursor", cursor);
  const payload = await apiJson<{ items?: unknown[]; next_cursor?: string; has_more?: boolean }>(
    `/users/${encodeURIComponent(id)}/posts?${params.toString()}`,
  );
  return {
    items: Array.isArray(payload.items) ? payload.items.map(parseProfilePost) : [],
    nextCursor: asString(payload.next_cursor) || undefined,
    hasMore: payload.has_more === true,
  };
}

export async function getMyProfileList(
  kind: "posts" | "comments" | "likes" | "bookmarks" | "history",
  cursor?: string,
  limit = 20,
): Promise<{ items: ProfilePost[]; nextCursor?: string; hasMore: boolean }> {
  const params = new URLSearchParams({ limit: String(limit) });
  if (cursor) params.set("cursor", cursor);
  const payload = await apiJson<{ items?: unknown[]; next_cursor?: string; has_more?: boolean }>(
    `/me/${kind}?${params.toString()}`,
  );
  return {
    items: Array.isArray(payload.items) ? payload.items.map(parseProfilePost) : [],
    nextCursor: asString(payload.next_cursor) || undefined,
    hasMore: payload.has_more === true,
  };
}

export async function getMyPoints(): Promise<{ points: number; experience: number }> {
  const payload = await apiJson<JsonRecord>("/me/points");
  return {
    points: asNumber(payload.balance ?? payload.points),
    experience: asNumber(payload.experience),
  };
}

export async function createReport(input: ReportInput): Promise<ReportResult> {
  const payload = await apiJson<JsonRecord>("/reports", {
    method: "POST",
    body: JSON.stringify({
      target_type: input.targetType,
      target_id: input.targetId,
      reason_code: input.reasonCode,
      description: input.description || "",
    }),
  });
  return {
    id: asString(payload.id),
    moderationCaseId: asString(payload.moderation_case_id),
    status: asString(payload.status),
  };
}

export async function setUserFollow(id: string, active: boolean): Promise<void> {
  await apiFetch(`/users/${encodeURIComponent(id)}/follow`, { method: active ? "PUT" : "DELETE" });
}

export async function searchForum(query: string): Promise<SearchResults> {
  const payload = await apiJson<JsonRecord>(`/search?q=${encodeURIComponent(query)}&type=all`);
  const posts = Array.isArray(payload.posts)
    ? payload.posts.map((raw) => {
        const item = asRecord(raw);
        return {
          id: asString(item.id),
          title: asString(item.title, "未命名帖子"),
          contentPreview: asString(item.content_preview, asString(item.content)),
          author: item.author ? parseUser(item.author) : undefined,
          community: item.community ? parseCommunity(item.community) : undefined,
          createdAt: asString(item.created_at) || undefined,
        };
      })
    : [];
  return {
    posts,
    users: Array.isArray(payload.users) ? payload.users.map(parseUser) : [],
    communities: Array.isArray(payload.communities) ? payload.communities.map(parseCommunity) : [],
    toys: Array.isArray(payload.toys) ? payload.toys.map(parseRankingToy) : [],
  };
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

export async function getRankingAdminView(tab = "", category = ""): Promise<RankingAdminView> {
  const params = new URLSearchParams();
  if (tab) params.set("tab", tab);
  if (category) params.set("category", category);
  const query = params.size ? `?${params.toString()}` : "";
  const payload = await apiJson<JsonRecord>(`/admin/ranking/views${query}`);
  const view = asRecord(payload.view);
  const weeklyTop = payload.weekly_top && typeof payload.weekly_top === "object" ? asRecord(payload.weekly_top) : null;
  return {
    tab: asString(view.tab),
    category: asString(view.category),
    sortMode: asString(view.sort_mode) === "MANUAL" ? "MANUAL" : "AUTO",
    version: asNumber(view.version),
    updatedBy: asString(view.updated_by),
    updatedAt: asString(view.updated_at) || undefined,
    items: Array.isArray(payload.items) ? payload.items.map(parseRankingAdminViewItem) : [],
    syncedAt: asString(payload.synced_at) || undefined,
    weeklyTop: weeklyTop
      ? {
          toyId: asString(weeklyTop.toy_id),
          name: asString(weeklyTop.name, "未命名产品"),
          coverUrl: resolveMediaUrl(asString(weeklyTop.cover_url), "thumb") ?? "",
          sourceRank: asNumber(weeklyTop.source_rank),
        }
      : undefined,
  };
}

function parseRankingAdminViewItem(raw: unknown): RankingAdminViewItem {
  const item = asRecord(raw);
  return {
    toyId: asString(item.toy_id),
    name: asString(item.name),
    coverUrl: resolveMediaUrl(asString(item.cover_url), "thumb") ?? "",
    sourceRank: asNumber(item.source_rank),
    manualPosition: item.manual_position == null ? undefined : asNumber(item.manual_position),
    displayPosition: asNumber(item.display_position),
  };
}

export async function saveRankingAdminViewOrder(input: {
  tab: string;
  category: string;
  mode: "AUTO" | "MANUAL";
  orderedToyIds: string[];
  version: number;
}): Promise<{ mode: "AUTO" | "MANUAL"; version: number }> {
  const payload = await apiJson<JsonRecord>("/admin/ranking/views/order", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      tab: input.tab,
      category: input.category,
      mode: input.mode,
      ordered_toy_ids: input.orderedToyIds,
      version: input.version,
    }),
  });
  return {
    mode: asString(payload.mode) === "MANUAL" ? "MANUAL" : "AUTO",
    version: asNumber(payload.version),
  };
}
