import '../../domain/models.dart';
import 'api_client.dart';

enum NotificationCategory {
  all('all'),
  interaction('interaction'),
  community('community'),
  moderation('moderation'),
  // 兼容已有调用方；新界面使用 interaction/community/moderation 三类。
  reply('reply'),
  like('like'),
  system('system');

  const NotificationCategory(this.value);

  final String value;
}

class NotificationPage {
  const NotificationPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ForumNotification> items;
  final String? nextCursor;
  final bool hasMore;
}

class ForumNotification {
  ForumNotification({
    required this.id,
    required this.type,
    this.actorId = '',
    required this.actorName,
    required this.targetType,
    required this.targetId,
    this.targetData = const <String, dynamic>{},
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String actorId;
  final String actorName;
  final String targetType;
  final String targetId;
  final Map<String, dynamic> targetData;
  bool isRead;
  final DateTime createdAt;

  bool get isModeration =>
      type.startsWith('moderation.') || type.startsWith('appeal.');

  bool get isSystem =>
      type == 'store.order.reviewed' || type == 'store.order.shipped';

  String? get moderationActionId {
    final value = targetData['moderation_action_id'];
    return value is String && value.isNotEmpty ? value : null;
  }

  NotificationCategory get category {
    if (isModeration) return NotificationCategory.moderation;
    if (isSystem) return NotificationCategory.system;
    if (type.startsWith('community.') ||
        type == 'announcement' ||
        type == 'event') {
      return NotificationCategory.community;
    }
    return NotificationCategory.interaction;
  }

  String get title {
    final customTitle = targetData['title'];
    if (customTitle is String && customTitle.isNotEmpty) return customTitle;
    return switch (type) {
      'like' || 'post.liked' =>
        targetType == 'comment' ? '$actorName 点赞了你的评论' : '$actorName 赞了你的帖子',
      'bookmark' || 'post.bookmarked' => '$actorName 收藏了你的帖子',
      'comment.created' || 'comment.replied' || 'reply' => '$actorName 回复了你的评论',
      'follow' || 'user.followed' => '$actorName 关注了你',
      'moderation.action' => switch (targetData['action']) {
        'mute' => '账号禁言通知',
        'ban' => '账号封禁通知',
        'delete' => '帖子处理通知',
        'hide' => '内容处理通知',
        _ => '处理通知',
      },
      'appeal.result' => switch (targetData['status']) {
        'approved' => '申诉已通过',
        'rejected' => '申诉未通过',
        _ => '申诉结果通知',
      },
      'store.order.reviewed' => '兑换申请审核结果',
      'store.order.shipped' => '兑换商品已发货',
      'announcement' || 'community.announcement' => '社区公告',
      'event' || 'community.event' => '活动通知',
      _ => '你有一条新通知',
    };
  }

  String get content {
    final customContent =
        targetData['content'] ??
        targetData['snippet'] ??
        targetData['message'] ??
        targetData['body'] ??
        targetData['reason'] ??
        targetData['post_title'] ??
        targetData['description'];
    if (customContent is String && customContent.isNotEmpty) {
      return customContent;
    }
    return '';
  }
}

class SearchToy {
  const SearchToy({
    required this.id,
    required this.rank,
    required this.name,
    required this.merchant,
    required this.releaseYear,
    required this.description,
    required this.tags,
    required this.assetKey,
    required this.wantCount,
    required this.ratingCount,
    required this.score,
    required this.category,
    required this.segments,
    this.coverUrl,
    this.couponUrl,
    this.sourceUrl,
  });

  final String id;
  final int rank;
  final String name;
  final String merchant;
  final int releaseYear;
  final String description;
  final List<String> tags;
  final String assetKey;
  final int wantCount;
  final int ratingCount;
  final double score;
  final String category;
  final List<String> segments;
  final String? coverUrl;
  final String? couponUrl;
  final String? sourceUrl;
}

class SearchPost {
  const SearchPost({
    required this.id,
    required this.title,
    required this.contentPreview,
    required this.communityId,
    required this.communityName,
    required this.createdAt,
    this.authorId = '',
    this.authorName = '',
    this.authorLevel = 1,
    this.commentCount = 0,
    this.likeCount = 0,
    this.viewCount = 0,
  });

  final String id;
  final String title;
  final String contentPreview;
  final String communityId;
  final String communityName;
  final DateTime createdAt;
  final String authorId;
  final String authorName;
  final int authorLevel;
  final int commentCount;
  final int likeCount;
  final int viewCount;
}

class SearchUser {
  const SearchUser({
    required this.id,
    required this.username,
    required this.nickname,
  });

  final String id;
  final String username;
  final String nickname;
}

class SearchCommunity {
  const SearchCommunity({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.followerCount,
  });

  final String id;
  final String slug;
  final String name;
  final String description;
  final int followerCount;
}

class SearchResult {
  const SearchResult({
    this.toys = const [],
    this.posts = const [],
    this.users = const [],
    this.communities = const [],
    this.nextCursor,
    this.hasMore = false,
  });

  final List<SearchToy> toys;
  final List<SearchPost> posts;
  final List<SearchUser> users;
  final List<SearchCommunity> communities;
  final String? nextCursor;
  final bool hasMore;

  bool get isEmpty =>
      toys.isEmpty && posts.isEmpty && users.isEmpty && communities.isEmpty;
}

class RankingItem {
  const RankingItem({
    required this.id,
    required this.title,
    required this.communityId,
    required this.score,
  });

  final String id;
  final String title;
  final String communityId;
  final double score;
}

class ModerationCase {
  const ModerationCase({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.source,
    required this.riskLevel,
    required this.status,
    required this.communityId,
    required this.createdAt,
  });

  final String id;
  final String targetType;
  final String targetId;
  final String source;
  final String riskLevel;
  final String status;
  final String communityId;
  final DateTime createdAt;
}

class ModerationCasePage {
  const ModerationCasePage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ModerationCase> items;
  final String? nextCursor;
  final bool hasMore;
}

/// 审核案件中的附件证据。
///
/// 审核案件可能对应待审核或已隐藏内容，图片不能依赖公开媒体网关；
/// [previewUrl] 始终指向需要管理员权限的预览接口。
class ModerationMediaEvidence {
  const ModerationMediaEvidence({
    required this.id,
    required this.type,
    required this.width,
    required this.height,
    required this.moderationStatus,
    this.thumbUrl,
    this.detailUrl,
    this.previewUrl,
  });

  final String id;
  final String type;
  final int width;
  final int height;
  final String moderationStatus;
  final String? thumbUrl;
  final String? detailUrl;
  final String? previewUrl;
}

class ModerationCaseDetail {
  const ModerationCaseDetail({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.source,
    required this.riskLevel,
    required this.status,
    required this.communityId,
    required this.createdAt,
    this.resolvedAt,
    this.target = const <String, dynamic>{},
    this.report = const <String, dynamic>{},
    this.account = const <String, dynamic>{},
    this.media = const <ModerationMediaEvidence>[],
  });

  final String id;
  final String targetType;
  final String targetId;
  final String source;
  final String riskLevel;
  final String status;
  final String communityId;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final Map<String, dynamic> target;
  final Map<String, dynamic> report;
  final Map<String, dynamic> account;
  final List<ModerationMediaEvidence> media;
}

class IpRestriction {
  const IpRestriction({
    required this.id,
    required this.cidr,
    required this.reason,
    required this.startsAt,
    required this.createdAt,
    this.endsAt,
    this.revokedAt,
  });

  final String id;
  final String cidr;
  final String reason;
  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime? revokedAt;
  final DateTime createdAt;

  bool get active =>
      revokedAt == null && (endsAt == null || endsAt!.isAfter(DateTime.now()));
}

class AccountPunishment {
  const AccountPunishment({
    required this.id,
    required this.type,
    required this.action,
    required this.reason,
    required this.startsAt,
    this.endsAt,
    required this.createdAt,
    this.appealable = false,
  });

  final String id;
  final String type;
  final String action;
  final String reason;
  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime createdAt;
  final bool appealable;
}

class AccountStatusData {
  const AccountStatusData({
    required this.userId,
    required this.username,
    required this.status,
    required this.accountType,
    required this.email,
    required this.emailVerified,
    required this.createdAt,
    required this.punishments,
  });

  final String userId;
  final String username;
  final String status;
  final String accountType;
  final String email;
  final bool emailVerified;
  final DateTime createdAt;
  final List<AccountPunishment> punishments;
}

class AdminSummary {
  const AdminSummary({
    required this.id,
    required this.username,
    required this.nickname,
    required this.email,
    required this.status,
    required this.roles,
    required this.actionCount,
    this.lastActionAt,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String nickname;
  final String email;
  final String status;
  final List<String> roles;
  final int actionCount;
  final DateTime? lastActionAt;
  final String? avatarUrl;
}

class AdminCandidate {
  const AdminCandidate({
    required this.id,
    required this.username,
    required this.nickname,
    required this.email,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String nickname;
  final String email;
  final String? avatarUrl;
}

class ManagedUserPage {
  const ManagedUserPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ManagedUserSummary> items;
  final String? nextCursor;
  final bool hasMore;
}

class ManagedUserSummary {
  const ManagedUserSummary({
    required this.id,
    required this.username,
    required this.nickname,
    required this.email,
    required this.status,
    required this.accountType,
    required this.createdAt,
    required this.roles,
    required this.banned,
    required this.muted,
  });

  final String id;
  final String username;
  final String nickname;
  final String email;
  final String status;
  final String accountType;
  final DateTime createdAt;
  final List<String> roles;
  final bool banned;
  final bool muted;
}

class ManagedUserDetail extends ManagedUserSummary {
  const ManagedUserDetail({
    required super.id,
    required super.username,
    required super.nickname,
    required super.email,
    required super.status,
    required super.accountType,
    required super.createdAt,
    required super.roles,
    required super.banned,
    required super.muted,
    required this.punishments,
    required this.recentPosts,
  });

  final List<Map<String, dynamic>> punishments;
  final List<Map<String, dynamic>> recentPosts;
}

class AdminRoleAssignment {
  const AdminRoleAssignment({required this.name, this.communityId});

  final String name;
  final String? communityId;
}

class AdminActionSummary {
  const AdminActionSummary({
    required this.id,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String action;
  final String targetType;
  final String targetId;
  final String reason;
  final DateTime createdAt;
}

class AdminDetail {
  const AdminDetail({
    required this.id,
    required this.username,
    required this.nickname,
    required this.email,
    required this.status,
    required this.roles,
    required this.permissions,
    required this.recentActions,
  });

  final String id;
  final String username;
  final String nickname;
  final String email;
  final String status;
  final List<Map<String, String>> roles;
  final List<String> permissions;
  final List<AdminActionSummary> recentActions;
}

class RiskEventSummary {
  const RiskEventSummary({
    required this.id,
    required this.eventType,
    required this.severity,
    required this.ipAddress,
    required this.createdAt,
    this.targetType = '',
    this.targetId = '',
    this.targetTitle = '',
    this.contentPreview = '',
    this.accountName = '',
    this.email = '',
  });

  final String id;
  final String eventType;
  final String severity;
  final String ipAddress;
  final DateTime createdAt;
  final String targetType;
  final String targetId;
  final String targetTitle;
  final String contentPreview;
  final String accountName;
  final String email;
}

class MediaModerationVersion {
  const MediaModerationVersion({
    required this.id,
    required this.mediaId,
    required this.versionNo,
    required this.moderationStatus,
    required this.maskRegions,
    required this.reason,
    required this.createdAt,
    required this.isInitial,
    this.operatorId,
  });

  final String id;
  final String mediaId;
  final int versionNo;
  final String moderationStatus;
  final List<MaskRegion> maskRegions;
  final String reason;
  final DateTime createdAt;
  final bool isInitial;
  final String? operatorId;
}

class RiskOverview {
  const RiskOverview({
    required this.codeRequests,
    required this.abnormalIps,
    required this.automaticRestrictions,
    required this.events,
  });

  final int codeRequests;
  final int abnormalIps;
  final int automaticRestrictions;
  final List<RiskEventSummary> events;
}

class AdminLogEntry {
  const AdminLogEntry({
    required this.id,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.previousHash,
    required this.hash,
    required this.createdAt,
    this.ipAddress = '',
  });

  final String id;
  final String action;
  final String targetType;
  final String targetId;
  final String reason;
  final String previousHash;
  final String hash;
  final String ipAddress;
  final DateTime createdAt;
}

class HomeRecommendation {
  const HomeRecommendation({
    required this.postId,
    required this.position,
    required this.recommendedBy,
    required this.recommendedAt,
    required this.title,
    required this.contentPreview,
    required this.authorName,
    required this.communityName,
    this.expiresAt,
  });

  final String postId;
  final int position;
  final String recommendedBy;
  final DateTime recommendedAt;
  final DateTime? expiresAt;
  final String title;
  final String contentPreview;
  final String authorName;
  final String communityName;
}

class RankingToySubmission {
  const RankingToySubmission({
    required this.id,
    required this.name,
    required this.category,
    required this.merchant,
    required this.description,
    required this.status,
    required this.reviewNote,
    required this.createdAt,
    required this.submitterId,
    required this.submitterNickname,
    required this.tags,
    this.releaseYear,
    this.coverUrl,
    this.toyId,
    this.intensity = '',
  });

  final String id;
  final String name;
  final String category;
  final String merchant;
  final int? releaseYear;
  final String description;
  final String? coverUrl;
  final String status;
  final String reviewNote;
  final String? toyId;
  final DateTime createdAt;
  final String submitterId;
  final String submitterNickname;
  final String intensity;
  final List<String> tags;
}

class AdminStoreOrder {
  const AdminStoreOrder({
    required this.id,
    required this.userId,
    required this.username,
    required this.nickname,
    required this.productId,
    required this.productName,
    required this.points,
    required this.status,
    required this.fulfillmentStatus,
    required this.createdAt,
    required this.userPoints,
    this.balanceAtSubmit = 0,
    this.hasBalanceAtSubmit = true,
    this.balanceSnapshotTrusted = true,
    this.invalidatedCount = 0,
    this.invalidatedPoints = 0,
    this.reviewedBy = '',
    this.reviewedAt,
    this.reviewReason = '',
    this.shippedAt,
    this.completedAt,
    this.shipping,
  });

  final String id;
  final String userId;
  final String username;
  final String nickname;
  final String productId;
  final String productName;
  final int points;
  final String status;
  final String fulfillmentStatus;
  final DateTime createdAt;
  final int userPoints;
  final int balanceAtSubmit;
  final bool hasBalanceAtSubmit;
  final bool balanceSnapshotTrusted;
  final int invalidatedCount;
  final int invalidatedPoints;
  final String reviewedBy;
  final DateTime? reviewedAt;
  final String reviewReason;
  final DateTime? shippedAt;
  final DateTime? completedAt;
  final AdminStoreOrderShipping? shipping;
}

class AdminStoreOrderDetail extends AdminStoreOrder {
  const AdminStoreOrderDetail({
    required super.id,
    required super.userId,
    required super.username,
    required super.nickname,
    required super.productId,
    required super.productName,
    required super.points,
    required super.status,
    required super.fulfillmentStatus,
    required super.createdAt,
    required super.userPoints,
    super.balanceAtSubmit,
    super.hasBalanceAtSubmit,
    super.balanceSnapshotTrusted,
    super.invalidatedCount,
    super.invalidatedPoints,
    super.reviewedBy,
    super.reviewedAt,
    super.reviewReason,
    super.shippedAt,
    super.completedAt,
    super.shipping,
    required this.reservedPoints,
    required this.availablePoints,
    required this.pointSources,
    this.historicalInvalidatedPoints = 0,
    this.eligiblePointsAtSubmit = 0,
  });

  final int reservedPoints;
  final int availablePoints;
  final List<StorePointSource> pointSources;
  final int historicalInvalidatedPoints;
  final int eligiblePointsAtSubmit;
}

class AdminStoreOrderShipping {
  const AdminStoreOrderShipping({
    required this.recipientName,
    required this.phone,
    required this.province,
    required this.city,
    required this.district,
    required this.addressDetail,
    this.carrier = '',
    this.trackingNo = '',
    this.maskedName = '',
    this.maskedPhone = '',
    this.maskedAddress = '',
    this.submittedAt,
    this.updatedAt,
  });

  final String recipientName;
  final String phone;
  final String province;
  final String city;
  final String district;
  final String addressDetail;
  final String carrier;
  final String trackingNo;
  final String maskedName;
  final String maskedPhone;
  final String maskedAddress;
  final DateTime? submittedAt;
  final DateTime? updatedAt;

  String get fullAddress => [
    province,
    city,
    district,
    addressDetail,
  ].where((part) => part.trim().isNotEmpty).join(' ');
}

class StorePointSource {
  const StorePointSource({
    required this.source,
    required this.points,
    required this.count,
    this.invalidPoints = 0,
  });

  final String source;
  final int points;
  final int count;
  final int invalidPoints;

  int get eligiblePoints => points - invalidPoints;
}

class AdminStoreOrderPage {
  const AdminStoreOrderPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<AdminStoreOrder> items;
  final String? nextCursor;
  final bool hasMore;
}

class AdminStoreRewardContent {
  const AdminStoreRewardContent({
    required this.id,
    required this.source,
    required this.targetType,
    required this.targetId,
    required this.points,
    required this.reason,
    required this.earnedAt,
    required this.titleAtReward,
    required this.contentAtReward,
    required this.currentTitle,
    required this.currentContent,
    required this.currentStatus,
    required this.editedSinceReward,
    required this.snapshotAvailable,
    this.invalidated = false,
    this.invalidationReason = '',
  });

  final String id;
  final String source;
  final String targetType;
  final String targetId;
  final int points;
  final String reason;
  final DateTime earnedAt;
  final String titleAtReward;
  final String contentAtReward;
  final String currentTitle;
  final String currentContent;
  final String currentStatus;
  final bool editedSinceReward;
  final bool snapshotAvailable;
  final bool invalidated;
  final String invalidationReason;
}

class AdminStoreRewardContentPage {
  const AdminStoreRewardContentPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<AdminStoreRewardContent> items;
  final String? nextCursor;
  final bool hasMore;
}

/// 管理端榜单视图中的单个条目。人工排序只在 [tab] 和 [category]
/// 对应的视图内生效，不能回写外部同步的源榜单名次。
class RankingViewOrderItem {
  const RankingViewOrderItem({
    required this.toyId,
    required this.name,
    required this.sourceRank,
  });

  final String toyId;
  final String name;
  final int sourceRank;
}

/// 一个可独立维护的榜单视图及其乐观锁版本。
class RankingViewOrder {
  const RankingViewOrder({
    required this.tab,
    required this.category,
    required this.version,
    required this.items,
  });

  final String tab;
  final String category;
  final int version;
  final List<RankingViewOrderItem> items;
}

class PlatformRepository {
  PlatformRepository(this._client);

  final ApiClient _client;

  Future<NotificationPage> listNotifications({
    String? cursor,
    int limit = 20,
    NotificationCategory category = NotificationCategory.all,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      'category': category.value,
    };
    if (cursor != null) query['cursor'] = cursor;
    final payload = await _client.getJson(
      '/api/v1/notifications',
      queryParameters: query,
    );
    final rawItems = payload['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map((item) {
            final value = Map<String, dynamic>.from(item);
            final actor = value['actor'] is Map
                ? Map<String, dynamic>.from(value['actor'] as Map)
                : <String, dynamic>{};
            return ForumNotification(
              id: _string(value['id']),
              type: _string(value['type']),
              actorId: _string(actor['id']),
              actorName: _string(actor['nickname']).isNotEmpty
                  ? _string(actor['nickname'])
                  : _string(actor['username']),
              targetType: _string(value['target_type']),
              targetId: _string(value['target_id']),
              targetData: value['target_data'] is Map
                  ? Map<String, dynamic>.from(value['target_data'] as Map)
                  : const <String, dynamic>{},
              isRead: value['is_read'] == true,
              createdAt: _date(value['created_at']),
            );
          }).toList()
        : <ForumNotification>[];
    return NotificationPage(
      items: items,
      nextCursor: payload['next_cursor'] as String?,
      hasMore: payload['has_more'] == true,
    );
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _client.patchJson('/api/v1/notifications/$notificationId/read');
  }

  Future<void> markAllNotificationsRead() async {
    await _client.postJson('/api/v1/notifications/read-all');
  }

  Future<int> unreadNotificationCount() async {
    final payload = await _client.getJson('/api/v1/notifications/unread-count');
    final value = payload['unread_count'];
    return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  }

  Future<SearchResult> search(
    String query, {
    String type = 'all',
    int limit = 20,
    String? cursor,
  }) async {
    final queryParameters = <String, String>{
      'q': query,
      'type': type,
      'limit': '$limit',
      'cursor': ?cursor,
    };
    final payload = await _client.getJson(
      '/api/v1/search',
      queryParameters: queryParameters,
    );
    return SearchResult(
      toys: _searchList(payload['toys'])
          .map(
            (value) => SearchToy(
              id: _string(value['id']),
              rank: _int(value['rank']),
              name: _string(value['name']),
              merchant: _string(value['merchant']),
              releaseYear: _int(value['release_year']),
              description: _string(value['description']),
              tags: (value['tags'] as List? ?? const [])
                  .map((e) => '$e')
                  .where((e) => e.isNotEmpty)
                  .toList(),
              assetKey: _string(value['asset_key']),
              wantCount: _int(value['want_count']),
              ratingCount: _int(value['rating_count']),
              score: _double(value['score']),
              category: _string(value['category'], fallback: 'cup'),
              segments: (value['segments'] as List? ?? const [])
                  .map((e) => '$e')
                  .where((e) => e.isNotEmpty)
                  .toList(),
              coverUrl: _nullableString(value['cover_url']),
              couponUrl: _nullableString(value['coupon_url']),
              sourceUrl: _nullableString(value['source_url']),
            ),
          )
          .toList(),
      posts: _searchList(payload['posts']).map((value) {
        final author = value['author'] is Map
            ? Map<String, dynamic>.from(value['author'] as Map)
            : const <String, dynamic>{};
        return SearchPost(
          id: _string(value['id']),
          title: _string(value['title']),
          contentPreview: _string(value['content_preview']),
          communityId: _string(value['community_id']),
          communityName: _string(value['community_name']),
          createdAt: _date(value['created_at']),
          authorId: _string(
            value['author_id'],
            fallback: _string(author['id']),
          ),
          authorName: _string(
            value['author_name'],
            fallback: _string(
              author['nickname'],
              fallback: _string(author['username'], fallback: '用户'),
            ),
          ),
          authorLevel: _int(
            value['author_level'],
            fallback: _int(author['level'], fallback: 1),
          ),
          commentCount: _int(value['comment_count']),
          likeCount: _int(value['like_count']),
          viewCount: _int(value['view_count']),
        );
      }).toList(),
      users: _searchList(payload['users'])
          .map(
            (value) => SearchUser(
              id: _string(value['id']),
              username: _string(value['username']),
              nickname: _string(value['nickname']),
            ),
          )
          .toList(),
      communities: _searchList(payload['communities'])
          .map(
            (value) => SearchCommunity(
              id: _string(value['id']),
              slug: _string(value['slug']),
              name: _string(value['name']),
              description: _string(value['description']),
              followerCount: _int(value['follower_count']),
            ),
          )
          .toList(),
      nextCursor: payload['next_cursor'] as String?,
      hasMore: payload['has_more'] == true,
    );
  }

  Future<Map<String, dynamic>> getHome() => _client.getJson('/api/v1/home');

  Future<List<HomeRecommendation>> listHomeRecommendations() async {
    final payload = await _client.getJson('/api/v1/admin/recommendations');
    final raw = payload['items'];
    if (raw is! List) return const <HomeRecommendation>[];
    return raw.whereType<Map>().map((item) {
      final value = Map<String, dynamic>.from(item);
      final post = value['post'] is Map
          ? Map<String, dynamic>.from(value['post'] as Map)
          : const <String, dynamic>{};
      final author = post['author'] is Map
          ? Map<String, dynamic>.from(post['author'] as Map)
          : const <String, dynamic>{};
      final community = post['community'] is Map
          ? Map<String, dynamic>.from(post['community'] as Map)
          : const <String, dynamic>{};
      final nickname = _string(author['nickname']);
      return HomeRecommendation(
        postId: _string(value['post_id'], fallback: _string(post['id'])),
        position: _int(value['position']),
        recommendedBy: _string(value['recommended_by']),
        recommendedAt: _date(value['recommended_at']),
        expiresAt: _nullableDate(value['expires_at']),
        title: _string(post['title'], fallback: '无标题'),
        contentPreview: _string(post['content_preview'] ?? post['content']),
        authorName: nickname.isNotEmpty
            ? nickname
            : _string(author['username']),
        communityName: _string(community['name']),
      );
    }).toList();
  }

  Future<void> setHomeRecommendation({
    required String postId,
    int? position,
    DateTime? expiresAt,
  }) async {
    await _client.putJson(
      '/api/v1/admin/recommendations/$postId',
      body: {
        'position': ?position,
        'expires_at': ?expiresAt?.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> removeHomeRecommendation(String postId) async {
    await _client.deleteJson('/api/v1/admin/recommendations/$postId');
  }

  Future<void> reorderHomeRecommendations(List<String> postIds) async {
    await _client.putJson(
      '/api/v1/admin/recommendations/reorder',
      body: {
        'items': [
          for (var index = 0; index < postIds.length; index++)
            {'post_id': postIds[index], 'position': index},
        ],
      },
    );
  }

  Future<void> setPostHotSuppression({
    required String postId,
    required bool suppressed,
    String? reason,
  }) async {
    await _client.putJson(
      '/api/v1/admin/posts/$postId/hot-suppression',
      body: {
        'suppressed': suppressed,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
  }

  Future<void> moderateMedia({
    required String mediaId,
    required String moderationStatus,
    List<MaskRegion> maskRegions = const [],
    String? reason,
  }) async {
    await _client.putJson(
      '/api/v1/admin/media/$mediaId/moderation',
      body: {
        'moderation_status': moderationStatus,
        'mask_regions': maskRegions.map((r) => r.toJson()).toList(),
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
  }

  /// 管理员重新审核已打码图片时读取真实源图；服务端只返回二进制，
  /// 不生成可缓存的公开 URL。
  Future<List<int>> getAdminMediaSource({required String mediaId}) {
    return _client.getBytes(
      '/api/v1/admin/media/$mediaId/source',
      headers: const {'Accept': 'image/*'},
    );
  }

  /// 获取媒体预览原始编码字节，用于有界解码，防止大图 OOM。
  /// 使用媒体网关 detail variant，限定在 API 域内，绝不接受任意外部 URL。
  Future<List<int>> getMediaPreviewBytesById(String mediaId) {
    return _client.getBytes(
      '/api/v1/media-file/$mediaId/detail',
      headers: const {'Accept': 'image/*'},
    );
  }

  /// 获取审核员专用的有界预览编码字节。
  ///
  /// 服务端优先返回 detail（打码媒体优先返回 censored_detail），缺失时
  /// 才回退到源图；响应始终 private/no-store，不能被公开缓存。
  Future<List<int>> getAdminMediaPreview({required String mediaId}) {
    return _client.getBytes(
      '/api/v1/admin/media/$mediaId/preview',
      headers: const {'Accept': 'image/*'},
    );
  }

  Future<List<MediaModerationVersion>> getMediaModerationHistory({
    required String mediaId,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/admin/media/$mediaId/moderation-history',
    );
    final raw = payload['items'];
    if (raw is! List) return const <MediaModerationVersion>[];
    return raw.whereType<Map>().map((item) {
      final value = Map<String, dynamic>.from(item);
      final rawRegions = value['mask_regions'];
      final regions = rawRegions is List
          ? rawRegions
                .whereType<Map>()
                .map(
                  (region) =>
                      MaskRegion.fromJson(Map<String, dynamic>.from(region)),
                )
                .toList()
          : const <MaskRegion>[];
      return MediaModerationVersion(
        id: _string(value['id']),
        mediaId: _string(value['media_id']),
        versionNo: _int(value['version_no']),
        moderationStatus: _string(value['moderation_status']),
        maskRegions: regions,
        reason: _string(value['reason']),
        createdAt: _date(value['created_at']),
        isInitial: value['is_initial'] == true,
        operatorId: _nullableString(value['operator_id']),
      );
    }).toList();
  }

  Future<List<RankingToySubmission>> listRankingSubmissions({
    String status = 'pending',
  }) async {
    final payload = await _client.getJson(
      '/api/v1/admin/ranking/submissions',
      queryParameters: {'status': status},
    );
    final raw = payload['items'];
    if (raw is! List) return const <RankingToySubmission>[];
    return raw.whereType<Map>().map((item) {
      final value = Map<String, dynamic>.from(item);
      final submitter = value['submitter'] is Map
          ? Map<String, dynamic>.from(value['submitter'] as Map)
          : const <String, dynamic>{};
      final releaseYear = value['release_year'];
      return RankingToySubmission(
        id: _string(value['id']),
        name: _string(value['name']),
        category: _string(value['category']),
        merchant: _string(value['merchant']),
        releaseYear: releaseYear is num ? releaseYear.toInt() : null,
        description: _string(value['description']),
        coverUrl: _nullableString(value['cover_url']),
        status: _string(value['status'], fallback: 'pending'),
        reviewNote: _string(value['review_note']),
        toyId: _nullableString(value['toy_id']),
        createdAt: _date(value['created_at']),
        submitterId: _string(submitter['id']),
        submitterNickname: _string(
          submitter['nickname'],
          fallback: _string(submitter['username']),
        ),
        intensity: _string(value['intensity']),
        tags: value['tags'] is List
            ? value['tags'].whereType<String>().toList()
            : const <String>[],
      );
    }).toList();
  }

  Future<void> reviewRankingSubmission({
    required String id,
    required bool approve,
    String? note,
  }) async {
    await _client.postJson(
      '/api/v1/admin/ranking/submissions/$id/review',
      body: {'action': approve ? 'approve' : 'reject', 'note': ?note},
    );
  }

  Future<List<AdminStoreOrder>> listStoreOrders({
    String status = 'pending_review',
    int limit = 50,
  }) async => (await listStoreOrderPage(status: status, limit: limit)).items;

  Future<AdminStoreOrderPage> listStoreOrderPage({
    String status = 'pending_review',
    int limit = 50,
    String? cursor,
  }) async {
    final query = <String, String>{
      'status': status,
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final payload = await _client.getJson(
      '/api/v1/admin/store/orders',
      queryParameters: query,
    );
    final raw = payload['items'];
    return AdminStoreOrderPage(
      items: raw is List
          ? raw.whereType<Map>().map(_adminStoreOrderFromJson).toList()
          : const <AdminStoreOrder>[],
      nextCursor: _nullableString(payload['next_cursor']),
      hasMore: payload['has_more'] == true,
    );
  }

  Future<AdminStoreOrderDetail> getStoreOrder(String id) async {
    final payload = await _client.getJson('/api/v1/admin/store/orders/$id');
    final rawSources = payload['point_sources'];
    final sources = rawSources is List
        ? rawSources.whereType<Map>().map((item) {
            final value = Map<String, dynamic>.from(item);
            return StorePointSource(
              source: _string(value['source']),
              points: _int(value['points']),
              count: _int(value['count']),
              invalidPoints: _int(value['invalid_points']),
            );
          }).toList()
        : const <StorePointSource>[];
    final base = _adminStoreOrderFromJson(payload);
    return AdminStoreOrderDetail(
      id: base.id,
      userId: base.userId,
      username: base.username,
      nickname: base.nickname,
      productId: base.productId,
      productName: base.productName,
      points: base.points,
      status: base.status,
      fulfillmentStatus: base.fulfillmentStatus,
      createdAt: base.createdAt,
      userPoints: base.userPoints,
      balanceAtSubmit: base.balanceAtSubmit,
      hasBalanceAtSubmit: base.hasBalanceAtSubmit,
      balanceSnapshotTrusted: base.balanceSnapshotTrusted,
      invalidatedCount: base.invalidatedCount,
      invalidatedPoints: base.invalidatedPoints,
      reviewedBy: base.reviewedBy,
      reviewedAt: base.reviewedAt,
      reviewReason: base.reviewReason,
      shippedAt: base.shippedAt,
      completedAt: base.completedAt,
      shipping: base.shipping,
      reservedPoints: _int(payload['reserved_points']),
      availablePoints: _int(payload['available_points']),
      pointSources: sources,
      historicalInvalidatedPoints: _int(
        payload['historical_invalidated_points'],
      ),
      eligiblePointsAtSubmit: _int(payload['eligible_points_at_submit']),
    );
  }

  Future<void> reviewStoreOrder({
    required String id,
    required String decision,
    String reason = '',
    List<String> invalidTransactionIds = const <String>[],
  }) async {
    await _client.postJson(
      '/api/v1/admin/store/orders/$id/review',
      body: {
        'decision': decision,
        'reason': reason,
        'invalid_transaction_ids': invalidTransactionIds,
      },
    );
  }

  Future<void> shipStoreOrder({
    required String id,
    required String carrier,
    required String trackingNo,
  }) async {
    await _client.postJson(
      '/api/v1/admin/store/orders/$id/ship',
      body: {'carrier': carrier, 'tracking_no': trackingNo},
    );
  }

  Future<List<AdminStoreRewardContent>> getStoreOrderRewardContent(
    String id,
  ) async => (await getStoreOrderRewardContentPage(id)).items;

  Future<AdminStoreRewardContentPage> getStoreOrderRewardContentPage(
    String id, {
    String? cursor,
    int limit = 50,
    String source = '',
    String status = '',
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      if (source.isNotEmpty) 'source': source,
      if (status.isNotEmpty) 'status': status,
    };
    final payload = await _client.getJson(
      '/api/v1/admin/store/orders/$id/reward-content',
      queryParameters: query,
    );
    final raw = payload['items'];
    final items = raw is List
        ? raw.whereType<Map>().map(_adminStoreRewardContentFromJson).toList()
        : const <AdminStoreRewardContent>[];
    return AdminStoreRewardContentPage(
      items: items,
      nextCursor: _nullableString(payload['next_cursor']),
      hasMore: payload['has_more'] == true,
    );
  }

  AdminStoreRewardContent _adminStoreRewardContentFromJson(dynamic raw) {
    final value = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    return AdminStoreRewardContent(
      id: _string(value['id']),
      source: _string(value['source']),
      targetType: _string(value['target_type']),
      targetId: _string(value['target_id']),
      points: _int(value['points']),
      reason: _string(value['reason']),
      earnedAt: _date(value['earned_at']),
      titleAtReward: _string(value['title_at_reward']),
      contentAtReward: _string(value['content_at_reward']),
      currentTitle: _string(value['current_title']),
      currentContent: _string(value['current_content']),
      currentStatus: _string(value['current_status']),
      editedSinceReward: value['edited_since_reward'] == true,
      snapshotAvailable: value['snapshot_available'] == true,
      invalidated: value['invalidated'] == true,
      invalidationReason: _string(value['invalidation_reason']),
    );
  }

  AdminStoreOrder _adminStoreOrderFromJson(dynamic raw) {
    final value = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    return AdminStoreOrder(
      id: _string(value['id']),
      userId: _string(value['user_id']),
      username: _string(value['username']),
      nickname: _string(
        value['nickname'],
        fallback: _string(value['username']),
      ),
      productId: _string(value['product_id']),
      productName: _string(value['product_name']),
      points: _int(value['points']),
      status: _string(value['status'], fallback: 'pending_review'),
      fulfillmentStatus: _string(value['fulfillment_status'], fallback: 'none'),
      createdAt: _date(value['created_at']),
      userPoints: _int(value['user_points']),
      balanceAtSubmit: _int(value['balance_at_submit']),
      hasBalanceAtSubmit: value.containsKey('balance_at_submit'),
      balanceSnapshotTrusted: value['balance_snapshot_trusted'] != false,
      invalidatedCount: _int(value['invalidated_count']),
      invalidatedPoints: _int(value['invalidated_points']),
      reviewedBy: _string(value['reviewed_by']),
      reviewedAt: _nullableDate(value['reviewed_at']),
      reviewReason: _string(value['review_reason']),
      shippedAt: _nullableDate(value['shipped_at']),
      completedAt: _nullableDate(value['completed_at']),
      shipping: _adminStoreOrderShippingFromJson(value['shipping']),
    );
  }

  AdminStoreOrderShipping? _adminStoreOrderShippingFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final value = Map<String, dynamic>.from(raw);
    return AdminStoreOrderShipping(
      recipientName: _string(value['recipient_name']),
      phone: _string(value['phone']),
      province: _string(value['province']),
      city: _string(value['city']),
      district: _string(value['district']),
      addressDetail: _string(value['address_detail']),
      carrier: _string(value['carrier']),
      trackingNo: _string(value['tracking_no']),
      maskedName: _string(value['masked_name']),
      maskedPhone: _string(value['masked_phone']),
      maskedAddress: _string(value['masked_address']),
      submittedAt: _nullableDate(value['submitted_at']),
      updatedAt: _nullableDate(value['updated_at']),
    );
  }

  /// 读取指定 Tab 和品类的排序视图。服务端返回的版本用于保存时防止
  /// 其他管理员或外部同步造成的覆盖。
  Future<RankingViewOrder> getRankingViewOrder({
    required String tab,
    required String category,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/admin/ranking/views',
      queryParameters: {
        if (tab.isNotEmpty) 'tab': tab,
        if (category.isNotEmpty) 'category': category,
      },
    );
    final view = payload['view'] is Map
        ? Map<String, dynamic>.from(payload['view'] as Map)
        : const <String, dynamic>{};
    final rawItems = payload['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map((item) {
            final value = Map<String, dynamic>.from(item);
            return RankingViewOrderItem(
              toyId: _string(value['toy_id']),
              name: _string(value['name']),
              sourceRank: _int(value['source_rank']),
            );
          }).toList()
        : const <RankingViewOrderItem>[];
    return RankingViewOrder(
      tab: _string(view['tab']),
      category: _string(view['category']),
      version: _int(view['version']),
      items: items,
    );
  }

  /// 仅保存当前 [tab] + [category] 视图的人工顺序。
  Future<int> saveRankingViewOrder({
    required String tab,
    required String category,
    required List<String> orderedToyIds,
    required int version,
  }) async {
    final payload = await _client.putJson(
      '/api/v1/admin/ranking/views/order',
      body: {
        'tab': tab,
        'category': category,
        'mode': 'MANUAL',
        'ordered_toy_ids': orderedToyIds,
        'version': version,
      },
    );
    return _int(payload['version']);
  }

  Future<List<RankingItem>> getRanking({
    String window = '24h',
    int limit = 20,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/ranking',
      queryParameters: {'window': window, 'limit': '$limit'},
    );
    final raw = payload['items'];
    if (raw is! List) return const <RankingItem>[];
    return raw.whereType<Map>().map((item) {
      final value = Map<String, dynamic>.from(item);
      final score = value['score'];
      return RankingItem(
        id: _string(value['id']),
        title: _string(value['title']),
        communityId: _string(value['community_id']),
        score: score is num ? score.toDouble() : double.tryParse('$score') ?? 0,
      );
    }).toList();
  }

  Future<ModerationCasePage> listModerationCases({
    String status = '',
    String? source,
    String? cursor,
    int limit = 20,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/moderation/cases',
      queryParameters: {
        'limit': '$limit',
        if (status.isNotEmpty) 'status': status,
        if (source != null && source.isNotEmpty) 'source': source,
        ...?(cursor == null ? null : {'cursor': cursor}),
      },
    );
    final raw = payload['items'];
    final items = raw is List
        ? raw.whereType<Map>().map((item) {
            final value = Map<String, dynamic>.from(item);
            return ModerationCase(
              id: _string(value['id']),
              targetType: _string(value['target_type']),
              targetId: _string(value['target_id']),
              source: _string(value['source']),
              riskLevel: _string(value['risk_level']),
              status: _string(value['status']),
              communityId: _string(value['community_id']),
              createdAt: _date(value['created_at']),
            );
          }).toList()
        : <ModerationCase>[];
    return ModerationCasePage(
      items: items,
      nextCursor: payload['next_cursor'] as String?,
      hasMore: payload['has_more'] == true,
    );
  }

  Future<void> applyModerationAction({
    required String caseId,
    required String action,
    String reason = '',
    int durationDays = 0,
    bool permanent = false,
  }) async {
    await _client.postJson(
      '/api/v1/moderation/cases/$caseId/actions',
      body: {
        'action': action,
        'reason': reason,
        if (action == 'mute' || action == 'ban') 'duration_days': durationDays,
        if (action == 'mute' || action == 'ban') 'permanent': permanent,
      },
    );
  }

  Future<ModerationCaseDetail> getModerationCase(String caseId) async {
    final payload = await _client.getJson('/api/v1/moderation/cases/$caseId');
    Map<String, dynamic> map(dynamic value) => value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return ModerationCaseDetail(
      id: _string(payload['id']),
      targetType: _string(payload['target_type']),
      targetId: _string(payload['target_id']),
      source: _string(payload['source']),
      riskLevel: _string(payload['risk_level']),
      status: _string(payload['status']),
      communityId: _string(payload['community_id']),
      createdAt: _date(payload['created_at']),
      resolvedAt: _nullableDate(payload['resolved_at']),
      target: map(payload['target']),
      report: map(payload['report']),
      account: map(payload['account']),
      media: _parseModerationMedia(map(payload['target'])['media']),
    );
  }

  Future<AccountStatusData> getAccountStatus() async {
    final payload = await _client.getJson('/api/v1/me/account-status');
    final raw = payload['punishments'];
    final punishments = raw is List
        ? raw.whereType<Map>().map((item) {
            final value = Map<String, dynamic>.from(item);
            return AccountPunishment(
              id: _string(value['id']),
              type: _string(value['type']),
              action: _string(value['action']),
              reason: _string(value['reason']),
              startsAt: _date(value['starts_at']),
              endsAt: _nullableDate(value['ends_at']),
              createdAt: _date(value['created_at']),
              appealable: value['appealable'] == true,
            );
          }).toList()
        : <AccountPunishment>[];
    return AccountStatusData(
      userId: _string(payload['user_id']),
      username: _string(payload['username']),
      status: _string(payload['status']),
      accountType: _string(payload['account_type']),
      email: _string(payload['email']),
      emailVerified: payload['email_verified'] == true,
      createdAt: _date(payload['created_at']),
      punishments: punishments,
    );
  }

  Future<List<AdminSummary>> listAdmins({String query = ''}) async {
    final payload = await _client.getJson(
      '/api/v1/admins',
      queryParameters: {if (query.trim().isNotEmpty) 'q': query.trim()},
    );
    final raw = payload['items'];
    if (raw is! List) return const <AdminSummary>[];
    return raw.whereType<Map>().map((item) {
      final value = Map<String, dynamic>.from(item);
      return AdminSummary(
        id: _string(value['id']),
        username: _string(value['username']),
        nickname: _string(value['nickname']),
        email: _string(value['email']),
        status: _string(value['status']),
        roles: value['roles'] is List
            ? (value['roles'] as List).whereType<String>().toList()
            : const <String>[],
        actionCount: _int(value['action_count']),
        lastActionAt: _nullableDate(value['last_action_at']),
        avatarUrl: _nullableString(value['avatar_url']),
      );
    }).toList();
  }

  Future<List<AdminCandidate>> listAdminCandidates({String query = ''}) async {
    final payload = await _client.getJson(
      '/api/v1/admins/candidates',
      queryParameters: {if (query.trim().isNotEmpty) 'q': query.trim()},
    );
    final raw = payload['items'];
    if (raw is! List) return const <AdminCandidate>[];
    return raw.whereType<Map>().map((item) {
      final value = Map<String, dynamic>.from(item);
      return AdminCandidate(
        id: _string(value['id']),
        username: _string(value['username']),
        nickname: _string(value['nickname']),
        email: _string(value['email']),
        avatarUrl: _nullableString(value['avatar_url']),
      );
    }).toList();
  }

  Future<ManagedUserPage> listManagedUsersPage({
    String query = '',
    String? status,
    String? cursor,
    int limit = 30,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/admin/users',
      queryParameters: {
        'limit': '$limit',
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (status != null && status.isNotEmpty) 'status': status,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final raw = payload['items'];
    final items = raw is List
        ? raw.whereType<Map>().map(_managedUserSummaryFromJson).toList()
        : const <ManagedUserSummary>[];
    return ManagedUserPage(
      items: items,
      nextCursor: payload['next_cursor'] as String?,
      hasMore: payload['has_more'] == true,
    );
  }

  Future<List<ManagedUserSummary>> listManagedUsers({
    String query = '',
    String? status,
    String? cursor,
    int limit = 30,
  }) async {
    final page = await listManagedUsersPage(
      query: query,
      status: status,
      cursor: cursor,
      limit: limit,
    );
    return page.items;
  }

  Future<ManagedUserDetail> getManagedUser(String userId) async {
    final value = await _client.getJson('/api/v1/admin/users/$userId');
    final summary = _managedUserSummaryFromJson(value);
    return ManagedUserDetail(
      id: summary.id,
      username: summary.username,
      nickname: summary.nickname,
      email: summary.email,
      status: summary.status,
      accountType: summary.accountType,
      createdAt: summary.createdAt,
      roles: summary.roles,
      banned: summary.banned,
      muted: summary.muted,
      punishments: _searchList(value['punishments']),
      recentPosts: _searchList(value['recent_posts']),
    );
  }

  Future<void> applyManagedUserAction({
    required String userId,
    required String action,
    required String reason,
    int durationDays = 0,
    bool permanent = false,
  }) async {
    await _client.postJson(
      '/api/v1/admin/users/$userId/actions',
      body: {
        'action': action,
        'reason': reason,
        'duration_days': durationDays,
        'permanent': permanent,
      },
    );
  }

  ManagedUserSummary _managedUserSummaryFromJson(Map value) {
    final rawRoles = value['roles'];
    final List<String> parsedRoles;
    if (rawRoles is List) {
      parsedRoles = rawRoles
          .map((item) {
            if (item is Map) {
              final name = _string(item['name']);
              final communityId = _string(item['community_id']);
              return communityId.isNotEmpty ? '$name:$communityId' : name;
            }
            final str = '$item'.trim();
            if (str.startsWith('{') && str.endsWith('}')) {
              final clean = str.substring(1, str.length - 1);
              final parts = clean.split(',');
              String n = '';
              String c = '';
              for (final part in parts) {
                final kv = part.split(':');
                if (kv.length >= 2) {
                  final k = kv[0].trim();
                  final v = kv.sublist(1).join(':').trim();
                  if (k == 'name') n = v;
                  if (k == 'community_id') c = v;
                }
              }
              if (n.isNotEmpty) {
                return c.isNotEmpty ? '$n:$c' : n;
              }
            }
            return str;
          })
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      parsedRoles = const <String>[];
    }
    return ManagedUserSummary(
      id: _string(value['id']),
      username: _string(value['username']),
      nickname: _string(value['nickname']),
      email: _string(value['email']),
      status: _string(value['status']),
      accountType: _string(value['account_type'], fallback: 'email'),
      createdAt: _date(value['created_at']),
      roles: parsedRoles,
      banned: value['banned'] == true,
      muted: value['muted'] == true,
    );
  }

  Future<void> updateAdminRoles({
    required String adminId,
    required List<AdminRoleAssignment> roles,
    required String reason,
  }) async {
    await _client.putJson(
      '/api/v1/admins/$adminId/roles',
      body: {
        'roles': roles
            .map(
              (role) => {
                'name': role.name,
                if (role.communityId != null) 'community_id': role.communityId,
              },
            )
            .toList(),
        'reason': reason,
      },
    );
  }

  Future<AdminDetail> getAdmin(String adminId) async {
    final payload = await _client.getJson('/api/v1/admins/$adminId');
    final rawRoles = payload['roles'];
    final rawActions = payload['recent_actions'];
    return AdminDetail(
      id: _string(payload['id']),
      username: _string(payload['username']),
      nickname: _string(payload['nickname']),
      email: _string(payload['email']),
      status: _string(payload['status']),
      roles: rawRoles is List
          ? rawRoles
                .whereType<Map>()
                .map(
                  (item) => {
                    'name': _string(item['name']),
                    'community_id': _string(item['community_id']),
                  },
                )
                .toList()
          : const <Map<String, String>>[],
      permissions: payload['permissions'] is List
          ? (payload['permissions'] as List).whereType<String>().toList()
          : const <String>[],
      recentActions: rawActions is List
          ? rawActions.whereType<Map>().map((item) {
              return AdminActionSummary(
                id: _string(item['id']),
                action: _string(item['action']),
                targetType: _string(item['target_type']),
                targetId: _string(item['target_id']),
                reason: _string(item['reason']),
                createdAt: _date(item['created_at']),
              );
            }).toList()
          : const <AdminActionSummary>[],
    );
  }

  Future<RiskOverview> getRiskOverview() async {
    final payload = await _client.getJson('/api/v1/admin/risk');
    final raw = payload['events'];
    final events = raw is List
        ? raw.whereType<Map>().map((item) {
            return RiskEventSummary(
              id: _string(item['id']),
              eventType: _string(item['event_type']),
              severity: _string(item['severity']),
              ipAddress: _string(item['ip_address']),
              createdAt: _date(item['created_at']),
              targetType: _string(item['target_type']),
              targetId: _string(item['target_id']),
              targetTitle: _string(item['target_title']),
              contentPreview: _string(item['content_preview']),
              accountName: _string(item['account_name']),
              email: _string(item['email']),
            );
          }).toList()
        : <RiskEventSummary>[];
    return RiskOverview(
      codeRequests: _int(payload['code_requests']),
      abnormalIps: _int(payload['abnormal_ips']),
      automaticRestrictions: _int(payload['automatic_restrictions']),
      events: events,
    );
  }

  Future<List<AdminLogEntry>> listAdminLogs() async {
    final payload = await _client.getJson('/api/v1/admin/logs');
    final raw = payload['items'];
    if (raw is! List) return const <AdminLogEntry>[];
    return raw.whereType<Map>().map((item) {
      return AdminLogEntry(
        id: _string(item['id']),
        action: _string(item['action']),
        targetType: _string(item['target_type']),
        targetId: _string(item['target_id']),
        reason: _string(item['reason']),
        previousHash: _string(item['previous_hash']),
        hash: _string(item['hash']),
        ipAddress: _string(item['ip_address']),
        createdAt: _date(item['created_at']),
      );
    }).toList();
  }

  Future<List<IpRestriction>> listIPRestrictions() async {
    final payload = await _client.getJson('/api/v1/admin/ip-restrictions');
    final raw = payload['items'];
    if (raw is! List) return const <IpRestriction>[];
    return raw.whereType<Map>().map((item) {
      final value = Map<String, dynamic>.from(item);
      return IpRestriction(
        id: _string(value['id']),
        cidr: _string(value['ip_cidr']),
        reason: _string(value['reason']),
        startsAt: _date(value['starts_at']),
        endsAt: _nullableDate(value['ends_at']),
        revokedAt: _nullableDate(value['revoked_at']),
        createdAt: _date(value['created_at']),
      );
    }).toList();
  }

  Future<void> createIPRestriction({
    required String cidr,
    required String reason,
    int durationDays = 0,
    bool permanent = false,
  }) async {
    await _client.postJson(
      '/api/v1/admin/ip-restrictions',
      body: {
        'ip_cidr': cidr,
        'reason': reason,
        'duration_days': durationDays,
        'permanent': permanent,
      },
    );
  }

  Future<void> revokeIPRestriction(String restrictionId) async {
    await _client.deleteJson('/api/v1/admin/ip-restrictions/$restrictionId');
  }

  Future<void> report({
    required String targetType,
    required String targetId,
    required String reasonCode,
    String description = '',
  }) async {
    await _client.postJson(
      '/api/v1/reports',
      body: {
        'target_type': targetType,
        'target_id': targetId,
        'reason_code': reasonCode,
        'description': description,
      },
    );
  }

  Future<void> setBlock({required String userId, required bool active}) async {
    final path = '/api/v1/users/$userId/block';
    if (active) {
      await _client.putJson(path);
    } else {
      await _client.deleteJson(path);
    }
  }

  Future<List<ActivityItem>> listAdminActivities({String? status}) async {
    final query = status != null && status.isNotEmpty ? '?status=$status' : '';
    final response = await _client.getJson('/api/v1/admin/activities$query');
    final items = response['items'] is List
        ? (response['items'] as List)
              .whereType<Map>()
              .map(
                (item) =>
                    ActivityItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <ActivityItem>[];
    return items;
  }

  Future<void> createAdminActivity({
    required String title,
    String description = '',
    String? coverMediaId,
    String? coverUrl,
    DateTime? startAt,
    DateTime? endAt,
    String location = '',
    String status = 'draft',
  }) async {
    await _client.postJson(
      '/api/v1/admin/activities',
      body: {
        'title': title,
        'description': description,
        if (coverMediaId != null && coverMediaId.isNotEmpty)
          'cover_media_id': coverMediaId,
        if (coverUrl != null && coverUrl.isNotEmpty) 'cover_url': coverUrl,
        if (startAt != null) 'start_at': startAt.toUtc().toIso8601String(),
        if (endAt != null) 'end_at': endAt.toUtc().toIso8601String(),
        'location': location,
        'status': status,
      },
    );
  }

  Future<void> updateAdminActivity({
    required String id,
    required String title,
    String description = '',
    String? coverMediaId,
    String? coverUrl,
    DateTime? startAt,
    DateTime? endAt,
    String location = '',
    String status = 'draft',
  }) async {
    await _client.putJson(
      '/api/v1/admin/activities/$id',
      body: {
        'title': title,
        'description': description,
        if (coverMediaId != null && coverMediaId.isNotEmpty)
          'cover_media_id': coverMediaId,
        if (coverUrl != null && coverUrl.isNotEmpty) 'cover_url': coverUrl,
        if (startAt != null) 'start_at': startAt.toUtc().toIso8601String(),
        if (endAt != null) 'end_at': endAt.toUtc().toIso8601String(),
        'location': location,
        'status': status,
      },
    );
  }

  Future<void> publishAdminActivity(String id) async {
    await _client.postJson(
      '/api/v1/admin/activities/$id/publish',
      body: const <String, dynamic>{},
    );
  }

  Future<void> offlineAdminActivity(String id) async {
    await _client.postJson(
      '/api/v1/admin/activities/$id/offline',
      body: const <String, dynamic>{},
    );
  }

  Future<void> deleteAdminActivity(String id) async {
    await _client.deleteJson('/api/v1/admin/activities/$id');
  }

  Future<List<ActivityItem>> listPublicActivities() async {
    final response = await _client.getJson('/api/v1/activities');
    final items = response['items'] is List
        ? (response['items'] as List)
              .whereType<Map>()
              .map(
                (item) =>
                    ActivityItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <ActivityItem>[];
    return items;
  }

  List<ModerationMediaEvidence> _parseModerationMedia(dynamic raw) {
    if (raw is! List) return const <ModerationMediaEvidence>[];
    return raw.whereType<Map>().map((item) {
      final value = Map<String, dynamic>.from(item);
      String? nullableString(dynamic rawValue) =>
          rawValue is String && rawValue.isNotEmpty ? rawValue : null;
      return ModerationMediaEvidence(
        id: _string(value['id']),
        type: _string(value['type'], fallback: 'image'),
        width: _int(value['width']),
        height: _int(value['height']),
        moderationStatus: _string(
          value['moderation_status'],
          fallback: 'normal',
        ),
        thumbUrl: nullableString(value['thumb_url']),
        detailUrl: nullableString(value['detail_url']),
        previewUrl: nullableString(value['preview_url']),
      );
    }).toList();
  }

  String _string(dynamic value, {String fallback = ''}) =>
      value is String && value.isNotEmpty ? value : fallback;

  String? _nullableString(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  int _int(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  double _double(dynamic value, {double fallback = 0.0}) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

  List<Map<String, dynamic>> _searchList(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : <Map<String, dynamic>>[];

  DateTime _date(dynamic value) => value is String
      ? DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
      : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  DateTime? _nullableDate(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;
}

class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.title,
    this.description = '',
    this.coverMediaId,
    this.coverUrl,
    this.startAt,
    this.endAt,
    this.location = '',
    required this.status,
    this.publicationStatus = 'draft',
    this.phase,
    required this.createdBy,
    this.authorName = '',
    this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String description;
  final String? coverMediaId;
  final String? coverUrl;
  final DateTime? startAt;
  final DateTime? endAt;
  final String location;
  final String status;
  final String publicationStatus;
  final String? phase;
  final String createdBy;
  final String authorName;
  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get statusLabel => switch (status) {
    'draft' => '草稿',
    'upcoming' => '未开始',
    'active' => '进行中',
    'ended' => '已结束',
    'offline' => '已下架',
    _ => status,
  };

  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    return ActivityItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      coverMediaId: json['cover_media_id'] as String?,
      coverUrl: json['cover_url'] as String?,
      startAt: json['start_at'] != null
          ? DateTime.tryParse(json['start_at'].toString())
          : null,
      endAt: json['end_at'] != null
          ? DateTime.tryParse(json['end_at'].toString())
          : null,
      location: json['location'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      publicationStatus:
          json['publication_status'] as String? ??
          ((json['status'] == 'draft' || json['status'] == 'offline')
              ? json['status'] as String
              : 'published'),
      phase: json['phase'] as String?,
      createdBy: json['created_by'] as String? ?? '',
      authorName: json['author_name'] as String? ?? '',
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class ApiPlatformRepository extends PlatformRepository {
  ApiPlatformRepository(super.client);
}
