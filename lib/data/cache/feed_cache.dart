import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models.dart';

/// Feed 只缓存可重新获取的列表快照；viewerState 按账号 scope 隔离。
class FeedCacheService {
  static const _prefix = 'luntan:feed:v1:';
  static const _maxAge = Duration(hours: 24);
  static const _maxEntries = 20;
  static const _maxTotalBytes = 8 * 1024 * 1024;

  Future<FeedPage?> read({
    required String accountScope,
    required String? communityId,
    required String sort,
    required LatestOrder latestOrder,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(accountScope, communityId, sort, latestOrder);
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final envelope = jsonDecode(raw);
      if (envelope is! Map || envelope['saved_at'] is! String) return null;
      final savedAt = DateTime.tryParse(envelope['saved_at'] as String);
      if (savedAt == null ||
          DateTime.now().toUtc().difference(savedAt) > _maxAge) {
        await prefs.remove(key);
        return null;
      }
      await prefs.setString(
        key,
        jsonEncode({
          ...Map<String, dynamic>.from(envelope),
          'last_accessed_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      final items = envelope['items'];
      if (items is! List) return null;
      return FeedPage(
        items: items
            .whereType<Map>()
            .map((item) => _postFromJson(Map<String, dynamic>.from(item)))
            .toList(),
        nextCursor: envelope['next_cursor'] as String?,
        hasMore: envelope['has_more'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required String accountScope,
    required String? communityId,
    required String sort,
    required LatestOrder latestOrder,
    required FeedPage page,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = jsonEncode({
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'last_accessed_at': DateTime.now().toUtc().toIso8601String(),
        'next_cursor': page.nextCursor,
        'has_more': page.hasMore,
        'items': page.items.map(_postToJson).toList(),
      });
      // Feed 快照过大时宁可放弃落盘，也不让缓存挤占应用的首要存储空间。
      if (utf8.encode(value).length <= 3 * 1024 * 1024) {
        await prefs.setString(
          _key(accountScope, communityId, sort, latestOrder),
          value,
        );
        await _trim(prefs);
      }
    } catch (_) {
      // 缓存失败不影响网络 Feed。
    }
  }

  Future<void> _trim(SharedPreferences prefs) async {
    final records = <_FeedCacheRecord>[];
    for (final key in prefs.getKeys().where(
      (item) => item.startsWith(_prefix),
    )) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final envelope = jsonDecode(raw);
        if (envelope is! Map || envelope['saved_at'] is! String) continue;
        final savedAt = DateTime.tryParse(envelope['saved_at'] as String);
        if (savedAt == null) continue;
        final lastAccessedAt =
            DateTime.tryParse(envelope['last_accessed_at'] as String? ?? '') ??
            savedAt;
        records.add(
          _FeedCacheRecord(
            key: key,
            bytes: utf8.encode(raw).length,
            lastAccessedAt: lastAccessedAt,
          ),
        );
      } catch (_) {
        await prefs.remove(key);
      }
    }
    records.sort((a, b) => a.lastAccessedAt.compareTo(b.lastAccessedAt));
    var totalBytes = records.fold<int>(0, (sum, item) => sum + item.bytes);
    while (records.length > _maxEntries || totalBytes > _maxTotalBytes) {
      final removed = records.removeAt(0);
      await prefs.remove(removed.key);
      totalBytes -= removed.bytes;
    }
  }

  String _key(
    String scope,
    String? communityId,
    String sort,
    LatestOrder order,
  ) => '$_prefix$scope:${communityId ?? 'all'}:$sort:${order.name}';
}

class _FeedCacheRecord {
  const _FeedCacheRecord({
    required this.key,
    required this.bytes,
    required this.lastAccessedAt,
  });

  final String key;
  final int bytes;
  final DateTime lastAccessedAt;
}

Map<String, dynamic> _postToJson(Post post) => {
  'id': post.id,
  'author_id': post.authorId,
  'community_id': post.communityId,
  'type': post.type.name,
  'publication_status': post.publicationStatus.name,
  'moderation_status': post.moderationStatus.name,
  'title': post.title,
  'content': post.content,
  'comment_count': post.commentCount,
  'like_count': post.likeCount,
  'bookmark_count': post.bookmarkCount,
  'share_count': post.shareCount,
  'view_count': post.viewCount,
  'created_at': post.createdAt.toIso8601String(),
  'updated_at': post.updatedAt.toIso8601String(),
  'published_at': post.publishedAt?.toIso8601String(),
  'activity_at': post.activityAt?.toIso8601String(),
  'last_comment_at': post.lastCommentAt?.toIso8601String(),
  'is_recommended': post.isRecommended,
  'recommendation_position': post.recommendationPosition,
  'hot_suppressed': post.hotSuppressed,
  'hot_suppressed_reason': post.hotSuppressedReason,
  'hot_suppressed_at': post.hotSuppressedAt?.toIso8601String(),
  'hot_suppressed_by': post.hotSuppressedBy,
  'tags': post.tags,
  'extra_tag': post.extraTag,
  'is_featured': post.isFeatured,
  'is_pinned': post.isPinned,
  'viewer_state': {
    'has_liked': post.viewerState.hasLiked,
    'has_bookmarked': post.viewerState.hasBookmarked,
    'is_following_author': post.viewerState.isFollowingAuthor,
    'is_following_community': post.viewerState.isFollowingCommunity,
    'is_community_member': post.viewerState.isCommunityMember,
    'can_edit': post.viewerState.canEdit,
    'can_delete': post.viewerState.canDelete,
    'can_report': post.viewerState.canReport,
  },
  'author': post.author == null ? null : _userToJson(post.author!),
  'community': post.community == null
      ? null
      : _communityToJson(post.community!),
  'media': post.media.map(_mediaToJson).toList(),
};

Map<String, dynamic> _userToJson(User user) => {
  'id': user.id,
  'username': user.username,
  'nickname': user.nickname,
  'avatar': user.avatar,
  'level': user.level,
  'status': user.status.name,
  'created_at': user.createdAt.toIso8601String(),
  'updated_at': user.updatedAt.toIso8601String(),
  'badge': user.badge,
  'signature': user.signature,
};

Map<String, dynamic> _communityToJson(Community value) => {
  'id': value.id,
  'slug': value.slug,
  'name': value.name,
  'description': value.description,
  'avatar': value.avatar,
  'banner': value.banner,
  'category_id': value.categoryId,
  'visibility': value.visibility.name,
  'join_policy': value.joinPolicy.name,
  'status': value.status.name,
  'member_count': value.memberCount,
  'follower_count': value.followerCount,
  'post_count': value.postCount,
  'sort_order': value.sortOrder,
  'is_following': value.isFollowing,
  'is_member': value.isMember,
  'can_publish': value.canPublish,
  'can_upload_media': value.canUploadMedia,
  'can_create_poll': value.canCreatePoll,
};

Map<String, dynamic> _mediaToJson(MediaAsset media) => {
  'id': media.id,
  'type': media.type.name,
  'url': media.url,
  'width': media.width,
  'height': media.height,
  'alt_text': media.altText,
  'moderation_status': media.moderationStatus,
  'mask_regions': media.maskRegions.map((region) => region.toJson()).toList(),
  'emoji': media.emoji,
  'label': media.label,
  'colors': media.colors,
  'thumb': _variantToJson(media.thumb),
  'feed': _variantToJson(media.feed),
  'detail': _variantToJson(media.detail),
  'original': _variantToJson(media.original),
};

Map<String, dynamic>? _variantToJson(MediaVariant? value) => value == null
    ? null
    : {
        'url': value.url,
        'width': value.width,
        'height': value.height,
        'size': value.sizeBytes,
        'mime_type': value.mimeType,
      };

Post _postFromJson(Map<String, dynamic> value) {
  final now = DateTime.now().toUtc();
  final viewer = _map(value['viewer_state']);
  final author = value['author'] is Map
      ? _userFromJson(_map(value['author']), now)
      : null;
  final community = value['community'] is Map
      ? _communityFromJson(_map(value['community']))
      : null;
  final media = value['media'] is List
      ? value['media']
            .whereType<Map>()
            .map((item) => _mediaFromJson(_map(item)))
            .toList()
      : <MediaAsset>[];
  return Post(
    id: value['id'] as String? ?? '',
    authorId: value['author_id'] as String? ?? '',
    communityId: value['community_id'] as String? ?? '',
    author: author,
    community: community,
    type: _enum(PostType.values, value['type'], PostType.normal),
    publicationStatus: _enum(
      PublicationStatus.values,
      value['publication_status'],
      PublicationStatus.published,
    ),
    moderationStatus: _enum(
      ModerationStatus.values,
      value['moderation_status'],
      ModerationStatus.normal,
    ),
    title: value['title'] as String? ?? '',
    content: value['content'] as String? ?? '',
    commentCount: _number(value['comment_count']),
    likeCount: _number(value['like_count']),
    bookmarkCount: _number(value['bookmark_count']),
    shareCount: _number(value['share_count']),
    viewCount: _number(value['view_count']),
    createdAt: _date(value['created_at'], now),
    updatedAt: _date(value['updated_at'], now),
    publishedAt: _nullableDate(value['published_at']),
    activityAt: _nullableDate(value['activity_at']),
    lastCommentAt: _nullableDate(value['last_comment_at']),
    isRecommended: value['is_recommended'] == true,
    recommendationPosition: value['recommendation_position'] as int?,
    hotSuppressed: value['hot_suppressed'] == true,
    hotSuppressedReason: value['hot_suppressed_reason'] as String?,
    hotSuppressedAt: _nullableDate(value['hot_suppressed_at']),
    hotSuppressedBy: value['hot_suppressed_by'] as String?,
    tags: value['tags'] is List
        ? (value['tags'] as List).whereType<String>().toList()
        : const <String>[],
    extraTag: value['extra_tag'] as String?,
    isFeatured: value['is_featured'] == true,
    isPinned: value['is_pinned'] == true,
    viewerState: ViewerPostState(
      hasLiked: viewer['has_liked'] == true,
      hasBookmarked: viewer['has_bookmarked'] == true,
      isFollowingAuthor: viewer['is_following_author'] == true,
      isFollowingCommunity: viewer['is_following_community'] == true,
      isCommunityMember: viewer['is_community_member'] == true,
      canEdit: viewer['can_edit'] == true,
      canDelete: viewer['can_delete'] == true,
      canReport: viewer['can_report'] != false,
    ),
    media: media,
  );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
int _number(dynamic value) => value is num ? value.toInt() : 0;
DateTime _date(dynamic value, DateTime fallback) =>
    value is String ? DateTime.tryParse(value) ?? fallback : fallback;
DateTime? _nullableDate(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;
T _enum<T extends Enum>(List<T> values, dynamic value, T fallback) =>
    values.firstWhere((item) => item.name == value, orElse: () => fallback);
User _userFromJson(Map<String, dynamic> value, DateTime now) => User(
  id: value['id'] as String? ?? '',
  username: value['username'] as String? ?? '',
  nickname: value['nickname'] as String? ?? '',
  avatar: value['avatar'] as String?,
  level: _number(value['level']),
  status: _enum(UserStatus.values, value['status'], UserStatus.active),
  createdAt: _date(value['created_at'], now),
  updatedAt: _date(value['updated_at'], now),
  badge: value['badge'] as String?,
  signature: value['signature'] as String?,
);
Community _communityFromJson(Map<String, dynamic> value) => Community(
  id: value['id'] as String? ?? '',
  slug: value['slug'] as String? ?? '',
  name: value['name'] as String? ?? '',
  description: value['description'] as String? ?? '',
  avatar: value['avatar'] as String?,
  banner: value['banner'] as String?,
  categoryId: value['category_id'] as String? ?? '',
  visibility: _enum(
    CommunityVisibility.values,
    value['visibility'],
    CommunityVisibility.public,
  ),
  joinPolicy: _enum(
    CommunityJoinPolicy.values,
    value['join_policy'],
    CommunityJoinPolicy.open,
  ),
  status: _enum(
    CommunityStatus.values,
    value['status'],
    CommunityStatus.active,
  ),
  memberCount: _number(value['member_count']),
  followerCount: _number(value['follower_count']),
  postCount: _number(value['post_count']),
  sortOrder: _number(value['sort_order']),
  isFollowing: value['is_following'] == true,
  isMember: value['is_member'] == true,
  canPublish: value['can_publish'] != false,
  canUploadMedia: value['can_upload_media'] != false,
  canCreatePoll: value['can_create_poll'] != false,
);
MediaVariant? _variantFromJson(dynamic value) {
  final map = _map(value);
  final url = map['url'];
  if (url is! String || url.isEmpty) return null;
  return MediaVariant(
    url: url,
    width: _number(map['width']),
    height: _number(map['height']),
    sizeBytes: map['size'] as int?,
    mimeType: map['mime_type'] as String?,
  );
}

MediaAsset _mediaFromJson(Map<String, dynamic> value) {
  final rawMasks = value['mask_regions'];
  final rawColors = value['colors'];
  return MediaAsset(
    id: value['id'] as String? ?? '',
    type: value['type'] == 'video' ? MediaType.video : MediaType.image,
    url: value['url'] as String?,
    width: value['width'] as int?,
    height: value['height'] as int?,
    altText: value['alt_text'] as String?,
    moderationStatus: value['moderation_status'] as String? ?? 'normal',
    maskRegions: rawMasks is List
        ? rawMasks
              .whereType<Map>()
              .map(
                (item) => MaskRegion.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const [],
    thumb: _variantFromJson(value['thumb']),
    feed: _variantFromJson(value['feed']),
    detail: _variantFromJson(value['detail']),
    original: _variantFromJson(value['original']),
    emoji: value['emoji'] as String? ?? '🖼️',
    label: value['label'] as String? ?? '图片',
    colors: rawColors is List
        ? rawColors.whereType<num>().map((item) => item.toInt()).toList()
        : const [0xFFB7D9FF, 0xFF6D9CDE],
  );
}
