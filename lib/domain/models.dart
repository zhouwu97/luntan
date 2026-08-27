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
}

enum PublicationStatus { draft, published, deleted }

enum ModerationStatus { normal, pending, limited, hidden, rejected }

enum CommentPublicationStatus { published, deleted }

enum LatestOrder { comment, post }

class GrowthState {
  const GrowthState({
    required this.level,
    required this.experience,
    required this.levelStartExperience,
    this.nextLevelExperience,
    required this.experienceInLevel,
    this.experienceRequiredInLevel,
    this.progress,
    this.levelLocked = false,
  });

  final int level;
  final int experience;
  final int levelStartExperience;
  final int? nextLevelExperience;
  final int experienceInLevel;
  final int? experienceRequiredInLevel;
  final double? progress;
  final bool levelLocked;

  factory GrowthState.fromJson(
    Map<String, dynamic>? json, {
    int fallbackLevel = 1,
    String accountType = 'email',
  }) {
    if (json == null) {
      final isGuest = accountType == 'guest';
      return GrowthState(
        level: isGuest ? 0 : fallbackLevel,
        experience: 0,
        levelStartExperience: 0,
        nextLevelExperience: isGuest ? null : 100,
        experienceInLevel: 0,
        experienceRequiredInLevel: isGuest ? null : 100,
        progress: isGuest ? null : 0.0,
        levelLocked: isGuest,
      );
    }
    final isGuest = accountType == 'guest';
    if (isGuest) {
      // 服务端和旧缓存都可能携带正式账号的等级字段；游客只继承经验，
      // 等级相关字段必须统一由账号类型覆盖，永久保持 0 级且不可升级。
      final experience = json['experience'] is num
          ? (json['experience'] as num).toInt()
          : 0;
      return GrowthState(
        level: 0,
        experience: experience,
        levelStartExperience: 0,
        nextLevelExperience: null,
        experienceInLevel: experience,
        experienceRequiredInLevel: null,
        progress: null,
        levelLocked: true,
      );
    }
    final parsedLevel = json['level'] is num
        ? (json['level'] as num).toInt()
        : (isGuest ? 0 : fallbackLevel);
    return GrowthState(
      level: parsedLevel,
      experience: json['experience'] is num
          ? (json['experience'] as num).toInt()
          : 0,
      levelStartExperience: json['level_start_experience'] is num
          ? (json['level_start_experience'] as num).toInt()
          : 0,
      nextLevelExperience: json['next_level_experience'] is num
          ? (json['next_level_experience'] as num).toInt()
          : null,
      experienceInLevel: json['experience_in_level'] is num
          ? (json['experience_in_level'] as num).toInt()
          : 0,
      experienceRequiredInLevel: json['experience_required_in_level'] is num
          ? (json['experience_required_in_level'] as num).toInt()
          : null,
      progress: json['level_progress'] is num
          ? (json['level_progress'] as num).toDouble()
          : null,
      levelLocked: json['level_locked'] is bool
          ? json['level_locked'] as bool
          : isGuest,
    );
  }
}

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
    this.canPublish = true,
    this.canUploadMedia = true,
    this.canCreatePoll = true,
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
  final bool canPublish;
  final bool canUploadMedia;
  final bool canCreatePoll;
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

class MediaVariant {
  const MediaVariant({
    required this.url,
    required this.width,
    required this.height,
    this.sizeBytes,
    this.mimeType,
  });

  final String url;
  final int width;
  final int height;
  final int? sizeBytes;
  final String? mimeType;
}

class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.type,
    this.url,
    this.width,
    this.height,
    this.altText,
    this.thumb,
    this.detail,
    this.original,
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
  final MediaVariant? thumb;
  final MediaVariant? detail;
  final MediaVariant? original;

  String? get previewUrl => thumb?.url ?? detail?.url ?? original?.url ?? url;
  String? get detailUrl => detail?.url ?? original?.url ?? thumb?.url ?? url;
  String? get originalUrl => original?.url ?? detail?.url ?? thumb?.url ?? url;

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
    this.activityAt,
    this.lastCommentAt,
    this.isRecommended = false,
    this.recommendationPosition,
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
  final DateTime? activityAt;
  final DateTime? lastCommentAt;
  final bool isRecommended;
  final int? recommendationPosition;
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
  int get level =>
      author?.level ??
      (authorId.startsWith('guest') || authorId.isEmpty ? 0 : 1);
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
    this.replyToUser,
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

  /// 服务端返回的回复目标快照，避免客户端用“用户”占位或猜测昵称。
  final User? replyToUser;
  final String content;
  int likeCount;
  bool isLiked;
  int replyCount;
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

String compactCountLabel(int count) {
  if (count >= 10000) {
    final value = (count / 10000).toStringAsFixed(1);
    return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}w';
  }
  if (count >= 1000) {
    final value = (count / 1000).toStringAsFixed(1);
    return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}k';
  }
  return '$count';
}
