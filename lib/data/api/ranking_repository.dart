import 'api_client.dart';

class RankingToy {
  const RankingToy({
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
    required this.wanted,
    required this.owned,
    this.category = 'cup',
    this.segments = const [],
    this.rating,
    this.coverUrl,
    this.heroUrl,
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
  final bool wanted;
  final bool owned;
  final String category;
  final List<String> segments;
  final int? rating;
  final String? coverUrl;
  final String? heroUrl;
  final String? couponUrl;
  final String? sourceUrl;

  RankingToy copyWith({bool? wanted, bool? owned}) {
    return RankingToy(
      id: id,
      rank: rank,
      name: name,
      merchant: merchant,
      releaseYear: releaseYear,
      description: description,
      tags: tags,
      assetKey: assetKey,
      wantCount: wantCount,
      ratingCount: ratingCount,
      score: score,
      wanted: wanted ?? this.wanted,
      owned: owned ?? this.owned,
      category: category,
      segments: segments,
      rating: rating,
      coverUrl: coverUrl,
      heroUrl: heroUrl,
      couponUrl: couponUrl,
      sourceUrl: sourceUrl,
    );
  }
}

/// 一次榜单拉取的结果：items 为当前视图的有序榜单，weeklyTop 为源站
/// 置顶主推位（可能与榜单条目重复，也可能独立存在）。
class RankingList {
  const RankingList({required this.items, this.weeklyTop});

  final List<RankingToy> items;
  final RankingToy? weeklyTop;
}

class RankingToyCommentMedia {
  const RankingToyCommentMedia({
    required this.url,
    this.width = 0,
    this.height = 0,
    this.mimeType = '',
  });

  final String url;
  final int width;
  final int height;
  final String mimeType;
}

class RankingToyComment {
  RankingToyComment({
    required this.id,
    required this.authorId,
    required this.username,
    required this.nickname,
    required this.level,
    required this.content,
    required this.likeCount,
    required this.isLiked,
    required this.createdAt,
    this.authorRating,
    this.rootId,
    this.parentId,
    this.replyToUserId,
    this.replyToUserNickname,
    this.replyCount = 0,
    this.media = const [],
    this.avatarUrl,
    this.replyPreview = const [],
  });

  final String id;
  final String authorId;
  final String username;
  final String nickname;
  final int level;
  final String content;
  final int likeCount;
  final bool isLiked;
  final DateTime createdAt;
  final int? authorRating;
  final String? rootId;
  final String? parentId;
  final String? replyToUserId;
  final String? replyToUserNickname;
  int replyCount;
  final List<RankingToyCommentMedia> media;
  final String? avatarUrl;
  final List<RankingToyComment> replyPreview;

  RankingToyComment copyWith({
    String? id,
    String? authorId,
    String? username,
    String? nickname,
    int? level,
    String? content,
    int? likeCount,
    bool? isLiked,
    DateTime? createdAt,
    int? authorRating,
    String? rootId,
    String? parentId,
    String? replyToUserId,
    String? replyToUserNickname,
    int? replyCount,
    List<RankingToyCommentMedia>? media,
    String? avatarUrl,
    List<RankingToyComment>? replyPreview,
  }) {
    return RankingToyComment(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      level: level ?? this.level,
      content: content ?? this.content,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt ?? this.createdAt,
      authorRating: authorRating ?? this.authorRating,
      rootId: rootId ?? this.rootId,
      parentId: parentId ?? this.parentId,
      replyToUserId: replyToUserId ?? this.replyToUserId,
      replyToUserNickname: replyToUserNickname ?? this.replyToUserNickname,
      replyCount: replyCount ?? this.replyCount,
      media: media ?? this.media,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      replyPreview: replyPreview ?? this.replyPreview,
    );
  }
}

class RankingToyCommentPage {
  const RankingToyCommentPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<RankingToyComment> items;
  final String? nextCursor;
  final bool hasMore;
}

class RankingToyDetail {
  static const _unspecified = Object();

  const RankingToyDetail({
    required this.toy,
    required this.comments,
    required this.commentSort,
    this.ratingDistribution = const {},
    this.commentsNextCursor,
    this.commentsHasMore = false,
  });

  final RankingToy toy;
  final List<RankingToyComment> comments;
  final String commentSort;
  final Map<int, int> ratingDistribution;
  final String? commentsNextCursor;
  final bool commentsHasMore;

  RankingToyDetail copyWith({
    RankingToy? toy,
    List<RankingToyComment>? comments,
    String? commentSort,
    Map<int, int>? ratingDistribution,
    Object? commentsNextCursor = _unspecified,
    bool? commentsHasMore,
  }) {
    return RankingToyDetail(
      toy: toy ?? this.toy,
      comments: comments ?? this.comments,
      commentSort: commentSort ?? this.commentSort,
      ratingDistribution: ratingDistribution ?? this.ratingDistribution,
      commentsNextCursor: identical(commentsNextCursor, _unspecified)
          ? this.commentsNextCursor
          : commentsNextCursor as String?,
      commentsHasMore: commentsHasMore ?? this.commentsHasMore,
    );
  }
}

class RankingRepository {
  RankingRepository(this._client);

  final ApiClient _client;

  Future<void> submitToy({
    required String name,
    required String category,
    String? merchant,
    int? releaseYear,
    String? description,
    String? coverMediaId,
    String? intensity,
    List<String> tags = const [],
  }) async {
    await _client.postJson(
      '/api/v1/ranking/submissions',
      body: {
        'name': name,
        'category': category,
        'merchant': ?merchant,
        'release_year': ?releaseYear,
        'description': ?description,
        'cover_media_id': ?coverMediaId,
        'intensity': ?intensity,
        if (tags.isNotEmpty) 'tags': tags,
      },
    );
  }

  Future<RankingList> list({String? tab, String? category}) async {
    final payload = await _client.getJson(
      '/api/v1/ranking/toys',
      queryParameters: {
        if (tab != null && tab.isNotEmpty) 'tab': tab,
        if (category != null && category.isNotEmpty) 'category': category,
      },
    );
    final raw = payload['items'];
    final items = raw is! List
        ? const <RankingToy>[]
        : raw
              .whereType<Map>()
              .map((item) => _toyFromJson(Map<String, dynamic>.from(item)))
              .toList();
    final weeklyTop = payload['weekly_top'] is Map
        ? _toyFromJson(Map<String, dynamic>.from(payload['weekly_top'] as Map))
        : null;
    return RankingList(items: items, weeklyTop: weeklyTop);
  }

  Future<RankingToyDetail> detail(
    String toyId, {
    String commentSort = 'weight',
  }) async {
    final payload = await _client.getJson(
      '/api/v1/ranking/toys/$toyId',
      queryParameters: {'comment_sort': commentSort},
    );
    final rawComments = payload['comments'];
    final comments = rawComments is List
        ? rawComments
              .whereType<Map>()
              .map((item) => _commentFromJson(Map<String, dynamic>.from(item)))
              .toList()
        : <RankingToyComment>[];
    final rawDist = payload['rating_distribution'];
    final ratingDistribution = <int, int>{};
    if (rawDist is Map) {
      for (final entry in rawDist.entries) {
        final key = int.tryParse('${entry.key}');
        final val = entry.value is num
            ? (entry.value as num).toInt()
            : int.tryParse('${entry.value}') ?? 0;
        if (key != null) {
          ratingDistribution[key] = val;
        }
      }
    }
    return RankingToyDetail(
      toy: _toyFromJson(payload),
      comments: comments,
      commentSort: _string(payload['comment_sort'], fallback: commentSort),
      ratingDistribution: ratingDistribution,
      commentsNextCursor: _nullableString(payload['comments_next_cursor']),
      commentsHasMore: payload['comments_has_more'] == true,
    );
  }

  Future<RankingToyCommentPage> listComments({
    required String toyId,
    String sort = 'weight',
    String? cursor,
    int limit = 20,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/ranking/toys/$toyId/comments',
      queryParameters: {
        'sort': sort,
        'limit': '$limit',
        ...?cursor == null ? null : {'cursor': cursor},
      },
    );
    return _commentPageFromJson(payload);
  }

  Future<RankingToyCommentPage> listReplies({
    required String commentId,
    String? cursor,
    int limit = 20,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/ranking/toy-comments/$commentId/replies',
      queryParameters: {
        'limit': '$limit',
        ...?cursor == null ? null : {'cursor': cursor},
      },
    );
    return _commentPageFromJson(payload);
  }

  Future<RankingToy> setWanted({required String toyId, required bool active}) {
    final path = '/api/v1/ranking/toys/$toyId/want';
    return (active ? _client.putJson(path) : _client.deleteJson(path)).then(
      (_) async => (await detail(toyId)).toy,
    );
  }

  Future<RankingToy> setOwned({required String toyId, required bool active}) {
    final path = '/api/v1/ranking/toys/$toyId/owned';
    return (active ? _client.putJson(path) : _client.deleteJson(path)).then(
      (_) async => (await detail(toyId)).toy,
    );
  }

  /// 管理员维护优惠券链接；传空串表示清除。
  Future<RankingToy> setCouponUrl({
    required String toyId,
    required String couponUrl,
  }) {
    return _client
        .putJson(
          '/api/v1/admin/ranking/toys/$toyId/coupon',
          body: {'coupon_url': couponUrl},
        )
        .then((_) async => (await detail(toyId)).toy);
  }

  Future<RankingToy> rate({required String toyId, required int score}) async {
    final payload = await _client.postJson(
      '/api/v1/ranking/toys/$toyId/rating',
      body: {'score': score},
    );
    return _toyFromJson(payload);
  }

  Future<RankingToyComment> createComment({
    required String toyId,
    required String content,
    String? parentId,
    String? replyToUserId,
  }) async {
    final payload = await _client.postJson(
      '/api/v1/ranking/toys/$toyId/comments',
      headers: {'Idempotency-Key': _newIdempotencyKey('toy-comment')},
      body: {
        'content': content,
        ...?parentId == null ? null : {'parent_id': parentId},
        ...?replyToUserId == null ? null : {'reply_to_user_id': replyToUserId},
      },
    );
    return _commentFromJson(payload);
  }

  Future<int> setCommentLike({
    required String commentId,
    required bool active,
  }) async {
    final path = '/api/v1/ranking/toy-comments/$commentId/like';
    final payload = active
        ? await _client.putJson(path)
        : await _client.deleteJson(path).then((_) => <String, dynamic>{});
    return _int(payload['like_count']);
  }

  Future<void> deleteComment(String commentId) async {
    await _client.deleteJson('/api/v1/ranking/toy-comments/$commentId');
  }

  String _newIdempotencyKey(String prefix) =>
      '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-${identityHashCode(this)}';
}

RankingToyCommentPage _commentPageFromJson(Map<String, dynamic> payload) {
  final rawItems = payload['items'];
  final items = rawItems is List
      ? rawItems
            .whereType<Map>()
            .map((item) => _commentFromJson(Map<String, dynamic>.from(item)))
            .toList()
      : <RankingToyComment>[];
  return RankingToyCommentPage(
    items: items,
    nextCursor: _nullableString(payload['next_cursor']),
    hasMore: payload['has_more'] == true,
  );
}

RankingToy _toyFromJson(Map<String, dynamic> json) {
  final viewerState = json['viewer_state'] is Map
      ? Map<String, dynamic>.from(json['viewer_state'] as Map)
      : const <String, dynamic>{};
  final rawTags = json['tags'];
  final tags = rawTags is List
      ? rawTags
            .map((value) => '$value')
            .where((value) => value.isNotEmpty)
            .toList()
      : const <String>[];
  final rawSegments = json['segments'];
  final segments = rawSegments is List
      ? rawSegments
            .map((value) => '$value')
            .where((value) => value.isNotEmpty)
            .toList()
      : const <String>[];
  String? nullableUrl(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;
  return RankingToy(
    id: _string(json['id']),
    rank: _int(json['rank']),
    name: _string(json['name']),
    merchant: _string(json['merchant']),
    releaseYear: _int(json['release_year']),
    description: _string(json['description']),
    tags: tags,
    assetKey: _string(json['asset_key']),
    wantCount: _int(json['want_count']),
    ratingCount: _int(json['rating_count']),
    score: _double(json['score']),
    category: _string(json['category'], fallback: 'cup'),
    segments: segments,
    wanted: viewerState['wanted'] == true,
    owned: viewerState['owned'] == true,
    rating: _nullableInt(viewerState['rating']),
    coverUrl: nullableUrl(json['cover_url']),
    heroUrl: nullableUrl(json['hero_url']),
    couponUrl: nullableUrl(json['coupon_url']),
    sourceUrl: nullableUrl(json['source_url']),
  );
}

RankingToyComment _commentFromJson(Map<String, dynamic> json) {
  final author = json['author'] is Map
      ? Map<String, dynamic>.from(json['author'] as Map)
      : const <String, dynamic>{};
  final rawMedia = json['media'];
  final media = rawMedia is List
      ? rawMedia
            .whereType<Map>()
            .map(
              (item) => RankingToyCommentMedia(
                url: _string(Map<String, dynamic>.from(item)['url']),
                width: _int(Map<String, dynamic>.from(item)['width']),
                height: _int(Map<String, dynamic>.from(item)['height']),
                mimeType: _string(Map<String, dynamic>.from(item)['mime_type']),
              ),
            )
            .where((item) => item.url.isNotEmpty)
            .toList()
      : const <RankingToyCommentMedia>[];
  final rawReplies = json['reply_preview'];
  final replyPreview = rawReplies is List
      ? rawReplies
            .whereType<Map>()
            .map((item) => _commentFromJson(Map<String, dynamic>.from(item)))
            .toList()
      : const <RankingToyComment>[];
  return RankingToyComment(
    id: _string(json['id']),
    authorId: _string(author['id']),
    username: _string(author['username']),
    nickname: _string(author['nickname']),
    level: _int(author['level'], fallback: 1),
    content: _string(json['content']),
    likeCount: _int(json['like_count']),
    isLiked:
        json['viewer_state'] is Map &&
        (json['viewer_state'] as Map)['has_liked'] == true,
    createdAt: _date(json['created_at']),
    authorRating: _nullableInt(
      json['author_rating'] ?? author['author_rating'],
    ),
    rootId: _nullableString(json['root_id']),
    parentId: _nullableString(json['parent_id']),
    replyToUserId: _nullableString(json['reply_to_user_id']),
    replyToUserNickname: _replyToUserNickname(json['reply_to_user']),
    replyCount: _int(json['reply_count']),
    media: media,
    avatarUrl: _nullableString(author['avatar_url']),
    replyPreview: replyPreview,
  );
}

String? _replyToUserNickname(dynamic raw) {
  if (raw is! Map) return null;
  final value = Map<String, dynamic>.from(raw);
  final nickname = _nullableString(value['nickname']);
  return nickname ?? _nullableString(value['username']);
}

String _string(dynamic value, {String fallback = ''}) =>
    value is String ? value : fallback;

int _int(dynamic value, {int fallback = 0}) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

int? _nullableInt(dynamic value) => value is num ? value.toInt() : null;

String? _nullableString(dynamic value) =>
    value is String && value.isNotEmpty ? value : null;

double _double(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

DateTime _date(dynamic value) => value is String
    ? DateTime.tryParse(value) ?? DateTime.now().toUtc()
    : DateTime.now().toUtc();
