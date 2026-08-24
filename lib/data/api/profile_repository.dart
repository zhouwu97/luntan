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

abstract class ProfileListItem {
  const ProfileListItem({required this.id, required this.communityName});

  final String id;
  final String communityName;
}

class ProfilePostItem extends ProfileListItem {
  const ProfilePostItem({
    required super.id,
    required super.communityName,
    required this.title,
    required this.contentPreview,
    required this.communityId,
    required this.commentCount,
    required this.likeCount,
    required this.bookmarkCount,
    required this.publishedAt,
  });

  final String title;
  final String contentPreview;
  final String communityId;
  final int commentCount;
  final int likeCount;
  final int bookmarkCount;
  final DateTime publishedAt;
}

class ProfileCommentItem extends ProfileListItem {
  const ProfileCommentItem({
    required super.id,
    required super.communityName,
    required this.postId,
    required this.postTitle,
    required this.content,
    required this.communityId,
    required this.createdAt,
  });

  final String postId;
  final String postTitle;
  final String content;
  final String communityId;
  final DateTime createdAt;
}

class ProfileListPage {
  const ProfileListPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ProfileListItem> items;
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
        ? raw.whereType<Map>().map((item) {
            final data = Map<String, dynamic>.from(item);
            return kind == 'comments'
                ? _commentFromJson(data)
                : _postFromJson(data);
          }).toList()
        : <ProfileListItem>[];
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
    final publishedAt = _date(
      value['published_at'] ?? value['created_at'],
      DateTime.now().toUtc(),
    );
    return ProfilePostItem(
      id: _string(value['id']),
      title: _string(value['title']),
      contentPreview: _string(value['content_preview']),
      communityId: _string(value['community_id']),
      communityName: _string(value['community_name']),
      commentCount: _int(value['comment_count']),
      likeCount: _int(value['like_count']),
      bookmarkCount: _int(value['bookmark_count']),
      publishedAt: publishedAt,
    );
  }

  ProfileCommentItem _commentFromJson(Map<String, dynamic> value) {
    final createdAt = _date(value['created_at'], DateTime.now().toUtc());
    return ProfileCommentItem(
      id: _string(value['id'] ?? value['comment_id']),
      postId: _string(value['post_id']),
      postTitle: _string(value['post_title']),
      content: _string(value['content']),
      communityId: _string(value['community_id']),
      communityName: _string(value['community_name']),
      createdAt: createdAt,
    );
  }

  DateTime _date(dynamic value, DateTime fallback) =>
      DateTime.tryParse('$value')?.toUtc() ?? fallback;
}
