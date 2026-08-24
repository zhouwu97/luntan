import 'api_client.dart';

enum NotificationCategory {
  all('all'),
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
    required this.actorId,
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
    this.posts = const [],
    this.users = const [],
    this.communities = const [],
    this.nextCursor,
    this.hasMore = false,
  });

  final List<SearchPost> posts;
  final List<SearchUser> users;
  final List<SearchCommunity> communities;
  final String? nextCursor;
  final bool hasMore;

  bool get isEmpty => posts.isEmpty && users.isEmpty && communities.isEmpty;
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
      posts: _searchList(payload['posts'])
          .map(
            (value) => SearchPost(
              id: _string(value['id']),
              title: _string(value['title']),
              contentPreview: _string(value['content_preview']),
              communityId: _string(value['community_id']),
              communityName: _string(value['community_name']),
              createdAt: _date(value['created_at']),
            ),
          )
          .toList(),
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
    String? cursor,
    int limit = 20,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/moderation/cases',
      queryParameters: {
        'limit': '$limit',
        if (status.isNotEmpty) 'status': status,
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
  }) async {
    await _client.postJson(
      '/api/v1/moderation/cases/$caseId/actions',
      body: {'action': action, 'reason': reason},
    );
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
