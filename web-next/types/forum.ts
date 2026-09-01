export interface UserSummary {
  id: string;
  username: string;
  nickname: string;
  level: number;
  avatarUrl?: string;
}

export interface SessionUser extends UserSummary {
  accountType?: string;
  email?: string;
  status?: string;
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
  canPublish?: boolean;
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
  viewerState: ViewerPostState;
}

export interface Comment {
  id: string;
  postId: string;
  author: UserSummary;
  content: string;
  likeCount: number;
  dislikeCount: number;
  replyCount: number;
  floor?: number;
  createdAt: string;
  updatedAt: string;
  viewerState: ViewerCommentState;
  replyPreview?: Comment[];
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
