export interface UserSummary {
  id: string;
  username: string;
  nickname: string;
  level: number;
  avatarUrl?: string;
}

export interface SessionUser extends UserSummary {
  accountType?: string;
  experience?: number;
  email?: string;
  status?: string;
  role?: string;
  capabilities?: Record<string, boolean>;
}

export interface ViewerPostState {
  hasLiked: boolean;
  hasBookmarked: boolean;
  isFollowingAuthor: boolean;
  isFollowingCommunity: boolean;
  canEdit: boolean;
  canDelete: boolean;
  canReport: boolean;
}

export interface ViewerCommentState {
  hasLiked: boolean;
  hasDisliked: boolean;
}

export interface MediaAsset {
  id: string;
  type: "image" | "video";
  url?: string;
  thumbUrl?: string;
  feedUrl?: string;
  detailUrl?: string;
  originalUrl?: string;
  width?: number;
  height?: number;
  altText?: string;
}

export interface Community {
  id: string;
  slug: string;
  name: string;
  description: string;
  memberCount: number;
  followerCount: number;
  postCount: number;
  sortOrder: number;
  status?: string;
  canPublish?: boolean;
  canUploadMedia?: boolean;
  canCreatePoll?: boolean;
  isFollowing?: boolean;
  isMember?: boolean;
}

export interface Post {
  id: string;
  authorId: string;
  communityId: string;
  author: UserSummary;
  community: Community;
  type: string;
  title: string;
  content: string;
  commentCount: number;
  likeCount: number;
  bookmarkCount: number;
  shareCount: number;
  viewCount: number;
  createdAt: string;
  updatedAt: string;
  publishedAt?: string;
  activityAt?: string;
  media: MediaAsset[];
  isFeatured?: boolean;
  isRecommended?: boolean;
  recommendationPosition?: number;
  viewerState: ViewerPostState;
}

export interface Comment {
  id: string;
  postId: string;
  author: UserSummary;
  content: string;
  media?: MediaAsset[];
  likeCount: number;
  dislikeCount: number;
  replyCount: number;
  floor?: number;
  createdAt: string;
  updatedAt: string;
  viewerState: ViewerCommentState;
  replyPreview?: Comment[];
}

export interface CommentPage {
  items: Comment[];
  total: number;
  hasMore: boolean;
}

export interface CommentContext {
  postId: string;
  commentId: string;
  rootId: string;
  parentId?: string;
  isRoot: boolean;
  rootComment?: Comment;
  targetComment?: Comment;
}

export interface ProfilePostPage {
  items: ProfilePost[];
  nextCursor?: string;
  hasMore: boolean;
}

export interface ProfileCommentItem {
  id: string;
  postId: string;
  postTitle?: string;
  content: string;
  createdAt: string;
  likeCount: number;
}

export interface ProfileCommentPage {
  items: ProfileCommentItem[];
  nextCursor?: string;
  hasMore: boolean;
}

export interface FeedPage {
  items: Post[];
  nextCursor?: string;
  hasMore: boolean;
}

export interface EmailCodeChallenge {
  expiresIn: number;
  retryAfter: number;
  delivery: string;
  devCode?: string;
}

export interface AuthSession {
  user: SessionUser;
  accessToken: string;
  expiresIn?: number;
}

export interface ProfileSummary extends UserSummary {
  bio: string;
  experience: number;
  postCount: number;
  commentCount: number;
  likeReceivedCount: number;
  followerCount: number;
  followingCount: number;
  publicId?: string;
  createdAt?: string;
  isFollowing: boolean;
  canFollow: boolean;
}

export interface ProfilePost {
  id: string;
  commentId?: string;
  activityAt?: string;
  title: string;
  contentPreview: string;
  communityName: string;
  commentCount: number;
  likeCount: number;
  viewCount: number;
  createdAt: string;
}

export interface ReportInput {
  targetType: "post" | "comment" | "user" | "community";
  targetId: string;
  reasonCode: string;
  description?: string;
}

export interface ReportResult {
  id: string;
  moderationCaseId: string;
  status: string;
}

export interface ActivityItem {
  id: string;
  title: string;
  description: string;
  coverUrl?: string;
  startAt?: string;
  endAt?: string;
  location: string;
  status: "upcoming" | "active" | "ended" | string;
  phase?: string;
  authorName: string;
}

export interface RankingToyViewerState {
  wanted: boolean;
  owned: boolean;
  rating?: number;
}

export interface RankingToy {
  id: string;
  rank: number;
  /** 源榜单名次；列表接口的 rank 是含人工覆盖的展示序号，两者并存。 */
  sourceRank?: number;
  name: string;
  merchant: string;
  description: string;
  tags: string[];
  score: number;
  wantCount: number;
  ratingCount: number;
  coverUrl?: string;
  heroUrl?: string;
  category?: string;
  segments?: string[];
  viewerState?: RankingToyViewerState;
  releaseYear?: number;
  couponUrl?: string;
  sourceUrl?: string;
}

export interface RankingToyComment {
  id: string;
  author: UserSummary;
  content: string;
  likeCount: number;
  replyCount: number;
  rootId?: string;
  parentId?: string;
  replyToUserId?: string;
  replyToUser?: UserSummary;
  createdAt: string;
  rating?: number;
  media: MediaAsset[];
  viewerState: { hasLiked: boolean };
  replyPreview?: RankingToyComment[];
}

export interface RankingToyCommentPage {
  items: RankingToyComment[];
  nextCursor?: string;
  hasMore: boolean;
}

export interface RankingToyDetail extends RankingToy {
  releaseYear: number;
  ratingDistribution: Record<string, number>;
  comments: RankingToyComment[];
  commentsNextCursor?: string;
  commentsHasMore: boolean;
  commentSort: "weight" | "latest" | string;
}

export interface ForumNotification {
  id: string;
  type: string;
  actor: UserSummary;
  targetType: string;
  targetId: string;
  targetData: Record<string, unknown>;
  isRead: boolean;
  createdAt: string;
}

export interface SearchPostResult {
  id: string;
  title: string;
  contentPreview: string;
  author?: UserSummary;
  community?: Community;
  createdAt?: string;
}

export interface SearchResults {
  posts: SearchPostResult[];
  users: UserSummary[];
  communities: Community[];
  toys: RankingToy[];
}

export interface RankingAdminViewItem {
  toyId: string;
  name: string;
  coverUrl: string;
  sourceRank: number;
  manualPosition?: number;
  displayPosition: number;
}

export interface RankingAdminWeeklyTop {
  toyId: string;
  name: string;
  coverUrl: string;
  sourceRank: number;
}

export interface RankingAdminView {
  tab: string;
  category: string;
  sortMode: "AUTO" | "MANUAL";
  version: number;
  updatedBy: string;
  updatedAt?: string;
  items: RankingAdminViewItem[];
  syncedAt?: string;
  weeklyTop?: RankingAdminWeeklyTop;
}
