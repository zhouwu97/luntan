/// 论坛领域模型。
///
/// Category 是论坛导航组织，Community 是真实发帖空间。
/// 例如“数码”可以是 Category，而“手机”“电脑”是不同的 Community。
library;

enum UserStatus { active, suspended, deleted }

enum CommunityVisibility { public, private, hidden }

enum CommunityJoinPolicy { open, approval, inviteOnly }

enum CommunityStatus { active, archived, closed }

enum PostType {
  normal,
  image,
  poll,
  gameShare,
  question,
  article,
  video,
  activity,
  market,
}

enum PublicationStatus { draft, published, deleted }

enum ModerationStatus { normal, pending, limited, hidden, rejected }

enum CommentPublicationStatus { published, deleted }

class User {
  const User({
    required this.id,
    required this.username,
    required this.nickname,
    this.avatar,
    this.level = 1,
    this.status = UserStatus.active,
    required this.createdAt,
    required this.updatedAt,
    this.badge,
    this.signature,
  });

  final String id;
  final String username;
  final String nickname;
  final String? avatar;
  final int level;
  final UserStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? badge;
  final String? signature;
}

class CommunityCategory {
  const CommunityCategory({
    required this.id,
    this.parentId,
    required this.name,
    required this.slug,
    this.icon,
    this.sortOrder = 0,
    this.status = CommunityStatus.active,
  });

  final String id;
  final String? parentId;
  final String name;
  final String slug;
  final String? icon;
  final int sortOrder;
  final CommunityStatus status;
}

class Community {
  const Community({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    this.avatar,
    this.banner,
    required this.categoryId,
    this.visibility = CommunityVisibility.public,
    this.joinPolicy = CommunityJoinPolicy.open,
    this.status = CommunityStatus.active,
    this.memberCount = 0,
    this.followerCount = 0,
    this.postCount = 0,
    this.sortOrder = 0,
    this.isFollowing = false,
    this.isMember = false,
  });

  final String id;
  final String slug;
  final String name;
  final String description;
  final String? avatar;
  final String? banner;
  final String categoryId;
  final CommunityVisibility visibility;
  final CommunityJoinPolicy joinPolicy;
  final CommunityStatus status;
  final int memberCount;
  final int followerCount;
  final int postCount;
  final int sortOrder;
  final bool isFollowing;
  final bool isMember;
}

class ViewerPostState {
  ViewerPostState({
    this.hasLiked = false,
    this.hasBookmarked = false,
    this.isFollowingAuthor = false,
    this.isFollowingCommunity = false,
    this.isCommunityMember = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canReport = true,
  });

  bool hasLiked;
  bool hasBookmarked;
  bool isFollowingAuthor;
  bool isFollowingCommunity;
  bool isCommunityMember;
  bool canEdit;
  bool canDelete;
  bool canReport;
}

enum MediaType { image, video }

class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.type,
    this.url,
    this.width,
    this.height,
    this.altText,
    this.emoji = '🖼️',
    this.label = '图片',
    this.colors = const [0xFFB7D9FF, 0xFF6D9CDE],
  });

  final String id;
  final MediaType type;
  final String? url;
  final int? width;
  final int? height;
  final String? altText;

  // Mock/占位图片的视觉字段，接入真实媒体服务后由 url 和元数据替代。
  final String emoji;
  final String label;
  final List<int> colors;
}

class Post {
  Post({
    required this.id,
    required this.authorId,
    required this.communityId,
    this.author,
    this.community,
    this.type = PostType.normal,
    this.publicationStatus = PublicationStatus.published,
    this.moderationStatus = ModerationStatus.normal,
    required this.title,
    required this.content,
    this.commentCount = 0,
    this.likeCount = 0,
    this.bookmarkCount = 0,
    this.shareCount = 0,
    this.viewCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
    ViewerPostState? viewerState,
    this.tags = const [],
    this.extraTag,
    this.isFeatured = false,
    this.isPinned = false,
    this.media = const [],
  }) : viewerState = viewerState ?? ViewerPostState();

  final String id;
  final String authorId;
  final String communityId;
  // 列表读模型可带作者/社区摘要；关系的唯一核心字段仍是 authorId/communityId。
  final User? author;
  final Community? community;
  final PostType type;
  final PublicationStatus publicationStatus;
  final ModerationStatus moderationStatus;
  String title;
  String content;
  int commentCount;
  int likeCount;
  int bookmarkCount;
  int shareCount;
  int viewCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final ViewerPostState viewerState;
  final List<String> tags;
  final String? extraTag;
  final bool isFeatured;
  final bool isPinned;
  final List<MediaAsset> media;

  // 这些 getter 是迁移期间给现有 UI 的兼容适配，不是持久化字段。
  String get body => content;
  int get comments => commentCount;
  set comments(int value) => commentCount = value;
  bool get isLiked => viewerState.hasLiked;
  set isLiked(bool value) => viewerState.hasLiked = value;
  bool get isBookmarked => viewerState.hasBookmarked;
  set isBookmarked(bool value) => viewerState.hasBookmarked = value;
  int get level => author?.level ?? 1;
  List<MediaAsset> get images => media;
  String get tag => tags.isEmpty ? community?.name ?? '' : tags.first;
  String get time => relativeTimeLabel(createdAt);
  String get views => compactCountLabel(viewCount);
}

class Comment {
  Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    this.author,
    this.rootId,
    this.parentId,
    this.replyToUserId,
    required this.content,
    this.likeCount = 0,
    this.isLiked = false,
    this.replyCount = 0,
    this.publicationStatus = CommentPublicationStatus.published,
    this.moderationStatus = ModerationStatus.normal,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String postId;
  final String authorId;
  final User? author;
  final String? rootId;
  final String? parentId;
  final String? replyToUserId;
  final String content;
  int likeCount;
  bool isLiked;
  final int replyCount;
  final CommentPublicationStatus publicationStatus;
  final ModerationStatus moderationStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class Reaction {
  const Reaction({
    required this.id,
    required this.userId,
    required this.targetId,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String targetId;
  final String type;
  final DateTime createdAt;
}

class FeedPage {
  const FeedPage({required this.items, this.nextCursor, this.hasMore = false});

  final List<Post> items;
  final String? nextCursor;
  final bool hasMore;
}

class PostDetail {
  const PostDetail({required this.post, this.comments = const []});

  final Post post;
  final List<Comment> comments;
}

String relativeTimeLabel(DateTime value, {DateTime? now}) {
  final delta = (now ?? DateTime.now()).difference(value);
  if (delta.inMinutes < 1) return '刚刚';
  if (delta.inHours < 1) return '${delta.inMinutes}分钟前';
  if (delta.inHours < 24) return '${delta.inHours}小时前';
  if (delta.inDays == 1) return '昨天';
  return '${delta.inDays}天前';
}

String compactCountLabel(int value) {
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
  }
  return '$value';
}
