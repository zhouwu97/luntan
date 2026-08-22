import '../../domain/models.dart';
import '../../domain/repositories.dart';
import 'api_client.dart';

class ApiCommunityRepository implements CommunityRepository {
  ApiCommunityRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Community>> getCommunities({
    String? categoryId,
    CommunityStatus? status,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/communities',
      queryParameters: {
        'category_id': ?categoryId,
        if (status != null) 'status': status.name,
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
}

class ApiFeedRepository implements FeedRepository {
  ApiFeedRepository(this._client);

  final ApiClient _client;

  @override
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20}) async {
    final payload = await _client.getJson(
      '/api/v1/feed/latest',
      queryParameters: {
        'limit': '$limit',
        'cursor': ?cursor,
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

class ApiPostRepository implements PostRepository {
  ApiPostRepository(this._client);

  final ApiClient _client;

  @override
  Future<PostDetail?> getPost(String id) async {
    try {
      final payload = await _client.getJson('/api/v1/posts/$id');
      return PostDetail(post: _postFromJson(payload));
    } on ApiException catch (error) {
      if (error.type == ApiErrorType.notFound) {
        return null;
      }
      rethrow;
    }
  }
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
  );
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
  final type = _enumByName(PostType.values, json['type'], PostType.normal);
  return Post(
    id: _string(json['id']),
    authorId: _string(authorJson['id']),
    communityId: _string(communityJson['id']),
    author: User(
      id: _string(authorJson['id']),
      username: _string(authorJson['username']),
      nickname: _string(authorJson['nickname']),
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
  );
}

T _enumByName<T extends Enum>(List<T> values, dynamic value, T fallback) {
  if (value is String) {
    for (final item in values) {
      if (item.name == value) return item;
    }
  }
  return fallback;
}

String _string(dynamic value) => value is String ? value : '';
int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
DateTime _date(dynamic value, DateTime fallback) =>
    value is String ? DateTime.tryParse(value) ?? fallback : fallback;
