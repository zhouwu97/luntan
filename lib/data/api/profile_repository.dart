import '../../domain/models.dart';
import 'api_client.dart';

class ProfileSummary {
  const ProfileSummary({
    required this.id,
    required this.username,
    required this.nickname,
    required this.level,
    required this.trustLevel,
    required this.signature,
    required this.postCount,
    required this.commentCount,
    required this.likeReceivedCount,
    required this.followerCount,
    required this.followingCount,
  });

  final String id;
  final String username;
  final String nickname;
  final int level;
  final String trustLevel;
  final String signature;
  final int postCount;
  final int commentCount;
  final int likeReceivedCount;
  final int followerCount;
  final int followingCount;
}

class ProfilePostItem {
  const ProfilePostItem({
    required this.id,
    required this.communityName,
    required this.title,
    required this.contentPreview,
    required this.communityId,
    required this.commentCount,
    required this.likeCount,
    required this.bookmarkCount,
    required this.publishedAt,
    this.activityAt,
    this.authorId = '',
    this.authorUsername = '',
    this.authorNickname = '',
    this.authorLevel = 1,
    this.communitySlug = '',
    this.postType = 'normal',
    this.viewCount = 0,
    this.shareCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.publicationStatus = PublicationStatus.published,
    this.moderationStatus = ModerationStatus.normal,
    this.viewerState,
    this.media = const [],
    this.isFeatured = false,
    this.isPinned = false,
  }) : createdAt = createdAt ?? publishedAt,
       updatedAt = updatedAt ?? publishedAt;

  final String id;
  final String communityName;
  final String title;
  final String contentPreview;
  final String communityId;
  final int commentCount;
  final int likeCount;
  final int bookmarkCount;
  final DateTime publishedAt;
  // “我的评论”列表按收到最新评论排序；普通帖子列表仍按发布时间排序。
  final DateTime? activityAt;
  final String authorId;
  final String authorUsername;
  final String authorNickname;
  final int authorLevel;
  final String communitySlug;
  final String postType;
  final int viewCount;
  final int shareCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final PublicationStatus publicationStatus;
  final ModerationStatus moderationStatus;
  final ViewerPostState? viewerState;
  final List<MediaAsset> media;
  final bool isFeatured;
  final bool isPinned;
}

class ProfileListPage {
  const ProfileListPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ProfilePostItem> items;
  final String? nextCursor;
  final bool hasMore;
}

class ProfileRepository {
  ProfileRepository(this._client);

  final ApiClient _client;

  Future<ProfileSummary> getProfile() async {
    final value = await _client.getJson('/api/v1/me/profile');
    return ProfileSummary(
      id: _string(value['id']),
      username: _string(value['username']),
      nickname: _string(value['nickname']),
      level: _int(value['level'], fallback: 1),
      trustLevel: _string(value['trust_level']),
      signature: _string(value['signature']),
      postCount: _int(value['post_count']),
      commentCount: _int(value['comment_count']),
      likeReceivedCount: _int(value['like_received_count']),
      followerCount: _int(value['follower_count']),
      followingCount: _int(value['following_count']),
    );
  }

  Future<ProfileListPage> list(
    String kind, {
    String? cursor,
    int limit = 20,
    bool includeDetails = false,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (cursor != null) query['cursor'] = cursor;
    if (includeDetails) query['include_details'] = '1';
    final value = await _client.getJson(
      '/api/v1/me/$kind',
      queryParameters: query,
    );
    final raw = value['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((item) => _postFromJson(Map<String, dynamic>.from(item)))
              .toList()
        : <ProfilePostItem>[];
    return ProfileListPage(
      items: items,
      nextCursor: value['next_cursor'] as String?,
      hasMore: value['has_more'] == true,
    );
  }

  Future<void> recordHistory(String postId) =>
      _client.postJson('/api/v1/posts/$postId/history').then((_) {});

  Future<void> clearHistory() => _client.deleteJson('/api/v1/me/history');

  String _string(dynamic value) => value is String ? value : '';
  int _int(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  ProfilePostItem _postFromJson(Map<String, dynamic> value) {
    final author = value['author'] is Map
        ? Map<String, dynamic>.from(value['author'] as Map)
        : const <String, dynamic>{};
    final community = value['community'] is Map
        ? Map<String, dynamic>.from(value['community'] as Map)
        : const <String, dynamic>{};
    final publishedAt = _date(
      value['published_at'] ?? value['created_at'],
      DateTime.now().toUtc(),
    );
    final createdAt = _date(value['created_at'], publishedAt);
    final updatedAt = _date(value['updated_at'], createdAt);
    final activityAt = value['activity_at'] == null
        ? null
        : _date(value['activity_at'], publishedAt);
    final viewer = value['viewer_state'] is Map
        ? Map<String, dynamic>.from(value['viewer_state'] as Map)
        : const <String, dynamic>{};
    final media = value['media'] is List
        ? (value['media'] as List).whereType<Map>().map((raw) {
            final item = Map<String, dynamic>.from(raw);
            return MediaAsset(
              id: _string(item['id']),
              type: item['type'] == 'video' ? MediaType.video : MediaType.image,
              url: _nullableString(item['url']),
              width: _nullableInt(item['width']),
              height: _nullableInt(item['height']),
              altText: _nullableString(item['alt_text']),
            );
          }).toList()
        : const <MediaAsset>[];
    final rawType = _string(value['type'] ?? value['post_type']);
    return ProfilePostItem(
      id: _string(value['id']),
      title: _string(value['title']),
      contentPreview: _string(value['content'] ?? value['content_preview']),
      communityId: _string(value['community_id'] ?? community['id']),
      communityName: _string(value['community_name'] ?? community['name']),
      commentCount: _int(value['comment_count']),
      likeCount: _int(value['like_count']),
      bookmarkCount: _int(value['bookmark_count']),
      publishedAt: publishedAt,
      activityAt: activityAt,
      authorId: _string(value['author_id'] ?? author['id']),
      authorUsername: _string(value['author_username'] ?? author['username']),
      authorNickname: _string(value['author_nickname'] ?? author['nickname']),
      authorLevel: _int(value['author_level'] ?? author['level'], fallback: 1),
      communitySlug: _string(value['community_slug'] ?? community['slug']),
      postType: rawType.isEmpty ? 'normal' : rawType,
      viewCount: _int(value['view_count']),
      shareCount: _int(value['share_count']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      publicationStatus: _enumByName(
        PublicationStatus.values,
        value['publication_status'],
        PublicationStatus.published,
      ),
      moderationStatus: _enumByName(
        ModerationStatus.values,
        value['moderation_status'],
        ModerationStatus.normal,
      ),
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
      isFeatured: value['is_featured'] == true,
      isPinned: value['is_pinned'] == true,
    );
  }

  DateTime _date(dynamic value, DateTime fallback) =>
      DateTime.tryParse('$value')?.toUtc() ?? fallback;

  String? _nullableString(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  int? _nullableInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  T _enumByName<T extends Enum>(List<T> values, dynamic value, T fallback) {
    if (value is String) {
      for (final item in values) {
        if (item.name == value) return item;
      }
    }
    return fallback;
  }
}
