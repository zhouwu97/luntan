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

class ProfileListPage {
  const ProfileListPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<Map<String, dynamic>> items;
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
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (cursor != null) query['cursor'] = cursor;
    final value = await _client.getJson(
      '/api/v1/me/$kind',
      queryParameters: query,
    );
    final raw = value['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
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
}
