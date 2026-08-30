import '../../domain/models.dart';
import 'api_client.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    this.publicId = '',
    required this.username,
    required this.nickname,
    required this.bio,
    required this.level,
    this.experience = 0,
    this.growth,
    required this.trustLevel,
    required this.status,
    required this.postCount,
    required this.followerCount,
    required this.followingCount,
    required this.createdAt,
    this.avatarMediaId,
    this.backgroundMediaId,
    this.backgroundUrl,
    this.isFollowing = false,
    this.isBlocked = false,
    this.canFollow = false,
  });

  final String id;
  final String publicId;
  final String username;
  final String nickname;
  final String bio;
  final int level;
  final int experience;
  final GrowthState? growth;
  final String trustLevel;
  final String status;
  final int postCount;
  final int followerCount;
  final int followingCount;
  final DateTime createdAt;
  final String? avatarMediaId;
  final String? backgroundMediaId;
  final String? backgroundUrl;
  final bool isFollowing;
  final bool isBlocked;
  final bool canFollow;
}

class UserPost {
  const UserPost({
    required this.id,
    required this.title,
    required this.contentPreview,
    required this.communityName,
    required this.commentCount,
    this.likeCount = 0,
    this.viewCount = 0,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String contentPreview;
  final String communityName;
  final int commentCount;
  final int likeCount;
  final int viewCount;
  final DateTime createdAt;
}

class UserPostPage {
  const UserPostPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<UserPost> items;
  final String? nextCursor;
  final bool hasMore;
}

class UserRelation {
  const UserRelation({
    required this.id,
    required this.username,
    required this.nickname,
    this.avatarMediaId,
    this.isFollowing = false,
    this.isBlocked = false,
    this.canFollow = false,
  });

  final String id;
  final String username;
  final String nickname;
  final String? avatarMediaId;
  final bool isFollowing;
  final bool isBlocked;
  final bool canFollow;
}

class UserRelationPage {
  const UserRelationPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<UserRelation> items;
  final String? nextCursor;
  final bool hasMore;
}

abstract interface class UserRepository {
  Future<UserProfile?> getProfile(String userId);

  Future<UserPostPage> listPosts(
    String userId, {
    String? cursor,
    int limit = 20,
  });

  Future<UserRelationPage> listFollowers(
    String userId, {
    String? cursor,
    int limit = 20,
  });

  Future<UserRelationPage> listFollowing(
    String userId, {
    String? cursor,
    int limit = 20,
  });

  Future<void> setFollow({required String userId, required bool active});

  Future<void> setBlock({required String userId, required bool active});
}

class ApiUserRepository implements UserRepository {
  ApiUserRepository(this._client);

  final ApiClient _client;

  @override
  Future<UserProfile?> getProfile(String userId) async {
    try {
      final value = await _client.getJson('/api/v1/users/$userId');
      final viewer = value['viewer_state'] is Map
          ? Map<String, dynamic>.from(value['viewer_state'] as Map)
          : const <String, dynamic>{};
      final rawLevel = _int(value['level'], fallback: 0);
      final exp = _int(value['experience'], fallback: 0);
      final accountType = _string(value['account_type']);
      final growth = value['growth'] is Map<String, dynamic>
          ? GrowthState.fromJson(
              value['growth'] as Map<String, dynamic>,
              fallbackLevel: rawLevel,
              accountType: accountType,
            )
          : GrowthState.fromJson(
              null,
              fallbackLevel: rawLevel,
              fallbackExperience: exp,
              accountType: accountType,
            );
      final level = growth.level;
      return UserProfile(
        id: _string(value['id']),
        publicId: _string(value['public_id']),
        username: _string(value['username']),
        nickname: _string(value['nickname']),
        bio: _string(value['bio']),
        level: level,
        experience: exp,
        growth: growth,
        trustLevel: _string(value['trust_level']),
        status: _string(value['status']),
        postCount: _int(value['post_count']),
        followerCount: _int(value['follower_count']),
        followingCount: _int(value['following_count']),
        createdAt: _date(value['created_at']),
        avatarMediaId: _nullable(value['avatar_media_id']),
        backgroundMediaId: _nullable(value['background_media_id']),
        backgroundUrl: _nullable(value['background_url']),
        isFollowing: viewer['is_following'] == true,
        isBlocked: viewer['is_blocked'] == true,
        canFollow: viewer['can_follow'] == true,
      );
    } on ApiException catch (error) {
      if (error.type == ApiErrorType.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<UserPostPage> listPosts(
    String userId, {
    String? cursor,
    int limit = 20,
  }) async {
    final value = await _client.getJson(
      '/api/v1/users/$userId/posts',
      queryParameters: {
        'limit': '$limit',
        ...?(cursor == null ? null : {'cursor': cursor}),
      },
    );
    final raw = value['items'];
    final items = raw is List
        ? raw.whereType<Map>().map((item) {
            final data = Map<String, dynamic>.from(item);
            return UserPost(
              id: _string(data['id']),
              title: _string(data['title']),
              contentPreview: _string(data['content_preview']),
              communityName: _string(data['community_name']),
              commentCount: _int(data['comment_count']),
              likeCount: _int(data['like_count']),
              viewCount: _int(data['view_count']),
              createdAt: _date(data['created_at']),
            );
          }).toList()
        : <UserPost>[];
    return UserPostPage(
      items: items,
      nextCursor: value['next_cursor'] as String?,
      hasMore: value['has_more'] == true,
    );
  }

  @override
  Future<UserRelationPage> listFollowers(
    String userId, {
    String? cursor,
    int limit = 20,
  }) => _listRelations(
    userId,
    relation: 'followers',
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<UserRelationPage> listFollowing(
    String userId, {
    String? cursor,
    int limit = 20,
  }) => _listRelations(
    userId,
    relation: 'following',
    cursor: cursor,
    limit: limit,
  );

  Future<UserRelationPage> _listRelations(
    String userId, {
    required String relation,
    String? cursor,
    required int limit,
  }) async {
    final value = await _client.getJson(
      '/api/v1/users/$userId/$relation',
      queryParameters: {
        'limit': '$limit',
        ...?(cursor == null ? null : {'cursor': cursor}),
      },
    );
    final raw = value['items'];
    final items = raw is List
        ? raw.whereType<Map>().map((item) {
            final data = Map<String, dynamic>.from(item);
            final viewer = data['viewer_state'] is Map
                ? Map<String, dynamic>.from(data['viewer_state'] as Map)
                : const <String, dynamic>{};
            return UserRelation(
              id: _string(data['id']),
              username: _string(data['username']),
              nickname: _string(data['nickname']),
              avatarMediaId: _nullable(data['avatar_media_id']),
              isFollowing: viewer['is_following'] == true,
              isBlocked: viewer['is_blocked'] == true,
              canFollow: viewer['can_follow'] == true,
            );
          }).toList()
        : <UserRelation>[];
    return UserRelationPage(
      items: items,
      nextCursor: value['next_cursor'] as String?,
      hasMore: value['has_more'] == true,
    );
  }

  @override
  Future<void> setFollow({required String userId, required bool active}) {
    final path = '/api/v1/users/$userId/follow';
    return active
        ? _client.putJson(path).then((_) {})
        : _client.deleteJson(path);
  }

  @override
  Future<void> setBlock({required String userId, required bool active}) {
    final path = '/api/v1/users/$userId/block';
    return active
        ? _client.putJson(path).then((_) {})
        : _client.deleteJson(path);
  }

  String _string(dynamic value) => value is String ? value : '';
  String? _nullable(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;
  int _int(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
  DateTime _date(dynamic value) => value is String
      ? DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
      : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

class MockUserRepository implements UserRepository {
  MockUserRepository({this.postCount = 0});

  final int postCount;

  @override
  Future<UserProfile?> getProfile(String userId) async {
    return UserProfile(
      id: userId,
      username: 'user_${userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}',
      nickname: '社区用户',
      bio: '这个人很懒，什么都没写',
      level: 1,
      experience: 0,
      growth: const GrowthState(
        level: 1,
        experience: 0,
        levelStartExperience: 0,
        nextLevelExperience: 50,
        experienceInLevel: 0,
        experienceRequiredInLevel: 50,
        progress: 0.0,
        levelLocked: false,
      ),
      trustLevel: 'new',
      status: 'active',
      postCount: postCount,
      followerCount: 0,
      followingCount: 0,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<UserPostPage> listPosts(
    String userId, {
    String? cursor,
    int limit = 20,
  }) async {
    return const UserPostPage(items: [], hasMore: false);
  }

  @override
  Future<UserRelationPage> listFollowers(
    String userId, {
    String? cursor,
    int limit = 20,
  }) async => const UserRelationPage(items: []);

  @override
  Future<UserRelationPage> listFollowing(
    String userId, {
    String? cursor,
    int limit = 20,
  }) async => const UserRelationPage(items: []);

  @override
  Future<void> setFollow({
    required String userId,
    required bool active,
  }) async {}

  @override
  Future<void> setBlock({required String userId, required bool active}) async {}
}
