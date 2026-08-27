import '../../domain/models.dart';
import '../../domain/repositories.dart';
import 'api_client.dart';

class ApiCommunityRepository
    implements CommunityRepository, CommunityMutationRepository {
  ApiCommunityRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Community>> getCommunities({
    String? categoryId,
    CommunityStatus? status,
    bool? canPublish,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/communities',
      queryParameters: {
        'category_id': ?categoryId,
        if (status != null) 'status': status.name,
        if (canPublish != null) 'can_publish': '$canPublish',
      },
    );
    final items = payload['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_communityFromJson)
        .toList();
  }

  @override
  Future<Community?> getCommunity(String id) async {
    try {
      final payload = await _client.getJson('/api/v1/communities/$id');
      return _communityFromJson(payload);
    } on ApiException catch (error) {
      if (error.type == ApiErrorType.notFound) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> setFollow({required String communityId, required bool active}) {
    final path = '/api/v1/communities/$communityId/follow';
    return active
        ? _client.putJson(path).then((_) {})
        : _client.deleteJson(path);
  }

  @override
  Future<void> setMembership({
    required String communityId,
    required bool active,
  }) {
    final path = '/api/v1/communities/$communityId/membership';
    return active
        ? _client.putJson(path).then((_) {})
        : _client.deleteJson(path);
  }
}

class ApiFeedRepository implements FeedRepository, QueryableFeedRepository {
  ApiFeedRepository(this._client);

  final ApiClient _client;

  @override
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20}) async {
    return getFeed(cursor: cursor, limit: limit);
  }

  @override
  Future<FeedPage> getFeed({
    String? cursor,
    int limit = 20,
    String? communityId,
    String sort = 'latest',
    LatestOrder latestOrder = LatestOrder.comment,
    String? postType,
    bool? hasMedia,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/feed/latest',
      queryParameters: {
        'limit': '$limit',
        'cursor': ?cursor,
        'community_id': ?communityId,
        'sort': sort,
        'latest_by': latestOrder.name,
        'post_type': ?postType,
        if (hasMedia != null) 'has_media': '$hasMedia',
        'include_details': '1',
      },
    );
    final rawItems = payload['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map<String, dynamic>>().map(_postFromJson).toList()
        : <Post>[];
    return FeedPage(
      items: items,
      nextCursor: payload['next_cursor'] as String?,
      hasMore: payload['has_more'] == true,
    );
  }
}

class ApiPostRepository implements PostRepository, PostMutationRepository {
  ApiPostRepository(this._client);

  final ApiClient _client;

  @override
  Future<PostDetail?> getPost(String id) async {
    try {
      final payload = await _client.getJson(
        '/api/v1/posts/$id',
        queryParameters: const {'include_details': '1'},
      );
      return PostDetail(post: _postFromJson(payload));
    } on ApiException catch (error) {
      if (error.type == ApiErrorType.notFound) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<Post> updatePost({
    required String postId,
    required String communityId,
    required String type,
    required String title,
    required String content,
    List<String> mediaIds = const [],
  }) async {
    final payload = await _client.patchJson(
      '/api/v1/posts/$postId',
      body: {
        'community_id': communityId,
        'type': type,
        'title': title,
        'content': content,
        'media_ids': mediaIds,
      },
    );
    return _postFromJson(payload);
  }

  @override
  Future<void> deletePost(String postId) =>
      _client.deleteJson('/api/v1/posts/$postId');
}

Community _communityFromJson(Map<String, dynamic> json) {
  return Community(
    id: _string(json['id']),
    slug: _string(json['slug']),
    name: _string(json['name']),
    description: _string(json['description']),
    categoryId: _string(json['category_id']),
    visibility: _enumByName(
      CommunityVisibility.values,
      json['visibility'],
      CommunityVisibility.public,
    ),
    joinPolicy: _enumByName(
      CommunityJoinPolicy.values,
      json['join_policy'],
      CommunityJoinPolicy.open,
    ),
    status: _enumByName(
      CommunityStatus.values,
      json['status'],
      CommunityStatus.active,
    ),
    memberCount: _int(json['member_count']),
    followerCount: _int(json['follower_count']),
    postCount: _int(json['post_count']),
    sortOrder: _int(json['sort_order']),
    isFollowing: _viewerBool(json, 'is_following'),
    isMember: _viewerBool(json, 'is_member'),
    canPublish: json['can_publish'] != false,
    canUploadMedia: json['can_upload_media'] != false,
    canCreatePoll: json['can_create_poll'] != false,
  );
}

bool _viewerBool(Map<String, dynamic> json, String key) {
  final state = json['viewer_state'];
  return state is Map && state[key] == true;
}

Post _postFromJson(Map<String, dynamic> json) {
  final authorJson = json['author'] is Map
      ? Map<String, dynamic>.from(json['author'] as Map)
      : <String, dynamic>{};
  final communityJson = json['community'] is Map
      ? Map<String, dynamic>.from(json['community'] as Map)
      : <String, dynamic>{};
  final now = DateTime.now().toUtc();
  final createdAt = _date(json['created_at'], now);
  final publishedAt = json['published_at'] == null
      ? null
      : _date(json['published_at'], createdAt);
  final activityAt = json['activity_at'] == null
      ? null
      : _date(json['activity_at'], publishedAt ?? createdAt);
  final lastCommentAt = json['last_comment_at'] == null
      ? null
      : _date(json['last_comment_at'], createdAt);
  final type = _postTypeFromWire(json['type']);
  final viewerJson = json['viewer_state'] is Map
      ? Map<String, dynamic>.from(json['viewer_state'] as Map)
      : const <String, dynamic>{};
  final media = json['media'] is List
      ? (json['media'] as List).whereType<Map>().map((raw) {
          final value = Map<String, dynamic>.from(raw);
          return MediaAsset(
            id: _string(value['id']),
            type: value['type'] == 'video' ? MediaType.video : MediaType.image,
            url: _nullableString(value['url']),
            width: _nullableInt(value['width']),
            height: _nullableInt(value['height']),
            altText: _nullableString(value['alt_text']),
            thumb: _parseVariant(value['thumb']),
            detail: _parseVariant(value['detail']),
            original: _parseVariant(value['original']),
          );
        }).toList()
      : const <MediaAsset>[];
  return Post(
    id: _string(json['id']),
    authorId: _string(authorJson['id']),
    communityId: _string(communityJson['id']),
    author: User(
      id: _string(authorJson['id']),
      username: _string(authorJson['username']),
      nickname: _string(authorJson['nickname']),
      level: _int(authorJson['level'], fallback: 1),
      createdAt: now,
      updatedAt: now,
    ),
    community: Community(
      id: _string(communityJson['id']),
      slug: _string(communityJson['slug']),
      name: _string(communityJson['name']),
      description: '',
      categoryId: '',
    ),
    type: type,
    publicationStatus: _enumByName(
      PublicationStatus.values,
      json['publication_status'],
      PublicationStatus.published,
    ),
    moderationStatus: _enumByName(
      ModerationStatus.values,
      json['moderation_status'],
      ModerationStatus.normal,
    ),
    title: _string(json['title']),
    content: _string(json['content'] ?? json['content_preview']),
    commentCount: _int(json['comment_count']),
    likeCount: _int(json['like_count']),
    bookmarkCount: _int(json['bookmark_count']),
    shareCount: _int(json['share_count']),
    viewCount: _int(json['view_count']),
    createdAt: createdAt,
    updatedAt: _date(json['updated_at'], createdAt),
    publishedAt: publishedAt,
    activityAt: activityAt,
    lastCommentAt: lastCommentAt,
    isRecommended: json['is_recommended'] == true,
    recommendationPosition: _nullableInt(json['recommendation_position']),
    viewerState: ViewerPostState(
      hasLiked: viewerJson['has_liked'] == true,
      hasBookmarked: viewerJson['has_bookmarked'] == true,
      isFollowingAuthor: viewerJson['is_following_author'] == true,
      isFollowingCommunity: viewerJson['is_following_community'] == true,
      isCommunityMember: viewerJson['is_community_member'] == true,
      canEdit: viewerJson['can_edit'] == true,
      canDelete: viewerJson['can_delete'] == true,
      canReport: viewerJson['can_report'] != false,
    ),
    media: media,
  );
}

PostType _postTypeFromWire(dynamic value) => switch (value) {
  'game_share' => PostType.gameShare,
  'image' => PostType.image,
  'poll' => PostType.poll,
  'question' => PostType.question,
  'article' => PostType.article,
  'video' => PostType.video,
  'activity' => PostType.activity,
  _ => PostType.normal,
};

T _enumByName<T extends Enum>(List<T> values, dynamic value, T fallback) {
  if (value is String) {
    for (final item in values) {
      if (item.name == value) return item;
    }
  }
  return fallback;
}

String _string(dynamic value) => value is String ? value : '';
String? _nullableString(dynamic value) =>
    value is String && value.isNotEmpty ? value : null;
int? _nullableInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value');
int _int(dynamic value, {int fallback = 0}) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
DateTime _date(dynamic value, DateTime fallback) =>
    value is String ? DateTime.tryParse(value) ?? fallback : fallback;

MediaVariant? _parseVariant(dynamic raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  final url = _nullableString(map['url']);
  if (url == null || url.isEmpty) return null;
  return MediaVariant(
    url: url,
    width: _int(map['width']),
    height: _int(map['height']),
    sizeBytes: _nullableInt(map['size']),
    mimeType: _nullableString(map['mime_type']),
  );
}
