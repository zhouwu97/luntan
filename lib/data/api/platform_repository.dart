import 'api_client.dart';

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
    required this.actorId,
    required this.actorName,
    required this.targetType,
    required this.targetId,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String actorId;
  final String actorName;
  final String targetType;
  final String targetId;
  bool isRead;
  final DateTime createdAt;
}

class SearchPost {
  const SearchPost({
    required this.id,
    required this.title,
    required this.contentPreview,
    required this.communityId,
    required this.communityName,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String contentPreview;
  final String communityId;
  final String communityName;
  final DateTime createdAt;
}

class SearchUser {
  const SearchUser({required this.id, required this.username, required this.nickname});

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
    this.posts = const [],
    this.users = const [],
    this.communities = const [],
  });

  final List<SearchPost> posts;
  final List<SearchUser> users;
  final List<SearchCommunity> communities;

  bool get isEmpty => posts.isEmpty && users.isEmpty && communities.isEmpty;
}

class PlatformRepository {
  PlatformRepository(this._client);

  final ApiClient _client;

  Future<NotificationPage> listNotifications({
    String? cursor,
    int limit = 20,
  }) async {
    final query = <String, String>{'limit': '$limit'};
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
    await _client.postJson('/api/v1/notifications/$notificationId/read');
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
  }) async {
    final payload = await _client.getJson(
      '/api/v1/search',
      queryParameters: {'q': query, 'type': type, 'limit': '$limit'},
    );
    return SearchResult(
      posts: _searchList(payload['posts'])
          .map((value) => SearchPost(
                id: _string(value['id']),
                title: _string(value['title']),
                contentPreview: _string(value['content_preview']),
                communityId: _string(value['community_id']),
                communityName: _string(value['community_name']),
                createdAt: _date(value['created_at']),
              ))
          .toList(),
      users: _searchList(payload['users'])
          .map((value) => SearchUser(
                id: _string(value['id']),
                username: _string(value['username']),
                nickname: _string(value['nickname']),
              ))
          .toList(),
      communities: _searchList(payload['communities'])
          .map((value) => SearchCommunity(
                id: _string(value['id']),
                slug: _string(value['slug']),
                name: _string(value['name']),
                description: _string(value['description']),
                followerCount: _int(value['follower_count']),
              ))
          .toList(),
    );
  }

  Future<Map<String, dynamic>> getHome() => _client.getJson('/api/v1/home');

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

  String _string(dynamic value) => value is String ? value : '';

  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

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
}

class ApiPlatformRepository extends PlatformRepository {
  ApiPlatformRepository(super.client);
}
