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
    this.rating,
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
  final int? rating;
}

class RankingToyComment {
  const RankingToyComment({
    required this.id,
    required this.authorId,
    required this.username,
    required this.nickname,
    required this.level,
    required this.content,
    required this.likeCount,
    required this.isLiked,
    required this.createdAt,
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
}

class RankingToyDetail {
  const RankingToyDetail({
    required this.toy,
    required this.comments,
    required this.commentSort,
  });

  final RankingToy toy;
  final List<RankingToyComment> comments;
  final String commentSort;
}

class RankingRepository {
  RankingRepository(this._client);

  final ApiClient _client;

  Future<List<RankingToy>> list() async {
    final payload = await _client.getJson('/api/v1/ranking/toys');
    final raw = payload['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => _toyFromJson(Map<String, dynamic>.from(item)))
        .toList();
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
    return RankingToyDetail(
      toy: _toyFromJson(payload),
      comments: comments,
      commentSort: _string(payload['comment_sort'], fallback: commentSort),
    );
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
  }) async {
    final payload = await _client.postJson(
      '/api/v1/ranking/toys/$toyId/comments',
      headers: {'Idempotency-Key': _newIdempotencyKey('toy-comment')},
      body: {'content': content},
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

  String _newIdempotencyKey(String prefix) =>
      '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-${identityHashCode(this)}';
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
    wanted: viewerState['wanted'] == true,
    owned: viewerState['owned'] == true,
    rating: _nullableInt(viewerState['rating']),
  );
}

RankingToyComment _commentFromJson(Map<String, dynamic> json) {
  final author = json['author'] is Map
      ? Map<String, dynamic>.from(json['author'] as Map)
      : const <String, dynamic>{};
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
  );
}

String _string(dynamic value, {String fallback = ''}) =>
    value is String ? value : fallback;

int _int(dynamic value, {int fallback = 0}) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

int? _nullableInt(dynamic value) => value is num ? value.toInt() : null;

double _double(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

DateTime _date(dynamic value) => value is String
    ? DateTime.tryParse(value) ?? DateTime.now().toUtc()
    : DateTime.now().toUtc();
