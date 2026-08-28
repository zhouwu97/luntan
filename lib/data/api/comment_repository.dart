import '../../domain/models.dart';
import 'api_client.dart';

class CommentPage {
  const CommentPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<Comment> items;
  final String? nextCursor;
  final bool hasMore;
}

abstract interface class CommentRepository {
  Future<CommentPage> listComments({
    required String postId,
    String? cursor,
    int limit,
  });

  Future<CommentPage> listReplies({
    required String commentId,
    String? cursor,
    int limit,
  });

  Future<Comment> createComment({
    required String postId,
    required String content,
    String? parentId,
    String? replyToUserId,
    List<String> mediaIds,
    String? stickerId,
  });

  Future<Comment> createReply({
    required String commentId,
    required String content,
    String? replyToUserId,
    List<String> mediaIds,
    String? stickerId,
  });

  Future<void> deleteComment(String commentId);
}

/// 可选的评论编辑能力。单独拆出接口以兼容已有的测试仓储和离线仓储。
abstract interface class CommentMutationRepository {
  Future<Comment> updateComment({
    required String commentId,
    required String content,
  });
}

/// API 评论创建需要在服务端按用户和请求键去重。
abstract interface class IdempotentCommentRepository {
  Future<Comment> createCommentWithIdempotency({
    required String postId,
    required String content,
    required String idempotencyKey,
    String? parentId,
    String? replyToUserId,
    List<String> mediaIds,
    String? stickerId,
  });

  Future<Comment> createReplyWithIdempotency({
    required String commentId,
    required String content,
    required String idempotencyKey,
    String? replyToUserId,
    List<String> mediaIds,
    String? stickerId,
  });
}

class ApiCommentRepository
    implements
        CommentRepository,
        CommentMutationRepository,
        IdempotentCommentRepository {
  ApiCommentRepository(this._client);

  final ApiClient _client;

  @override
  Future<CommentPage> listComments({
    required String postId,
    String? cursor,
    int limit = 20,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/posts/$postId/comments',
      queryParameters: {'limit': '$limit', 'cursor': ?cursor},
    );
    final rawItems = payload['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((item) => _commentFromJson(Map<String, dynamic>.from(item)))
              .toList()
        : <Comment>[];
    return CommentPage(
      items: items,
      nextCursor: payload['next_cursor'] as String?,
      hasMore: payload['has_more'] == true,
    );
  }

  @override
  Future<CommentPage> listReplies({
    required String commentId,
    String? cursor,
    int limit = 20,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/comments/$commentId/replies',
      queryParameters: {'limit': '$limit', 'cursor': ?cursor},
    );
    final rawItems = payload['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((item) => _commentFromJson(Map<String, dynamic>.from(item)))
              .toList()
        : <Comment>[];
    return CommentPage(
      items: items,
      nextCursor: payload['next_cursor'] as String?,
      hasMore: payload['has_more'] == true,
    );
  }

  @override
  Future<Comment> createComment({
    required String postId,
    required String content,
    String? parentId,
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
  }) async {
    return createCommentWithIdempotency(
      postId: postId,
      content: content,
      idempotencyKey: _newIdempotencyKey('comment'),
      parentId: parentId,
      replyToUserId: replyToUserId,
      mediaIds: mediaIds,
      stickerId: stickerId,
    );
  }

  @override
  Future<Comment> createReply({
    required String commentId,
    required String content,
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
  }) async {
    return createReplyWithIdempotency(
      commentId: commentId,
      content: content,
      idempotencyKey: _newIdempotencyKey('reply'),
      replyToUserId: replyToUserId,
      mediaIds: mediaIds,
      stickerId: stickerId,
    );
  }

  @override
  Future<Comment> createCommentWithIdempotency({
    required String postId,
    required String content,
    required String idempotencyKey,
    String? parentId,
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
  }) async {
    final body = <String, dynamic>{'content': content};
    if (parentId != null) body['parent_id'] = parentId;
    if (replyToUserId != null) body['reply_to_user_id'] = replyToUserId;
    if (mediaIds.isNotEmpty) body['media_ids'] = mediaIds;
    if (stickerId != null && stickerId.isNotEmpty) body['sticker_id'] = stickerId;
    final payload = await _client.postJson(
      '/api/v1/posts/$postId/comments',
      headers: {'Idempotency-Key': idempotencyKey},
      body: body,
    );
    return _commentFromJson(payload);
  }

  @override
  Future<Comment> createReplyWithIdempotency({
    required String commentId,
    required String content,
    required String idempotencyKey,
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
  }) async {
    final body = <String, dynamic>{'content': content};
    if (replyToUserId != null) body['reply_to_user_id'] = replyToUserId;
    if (mediaIds.isNotEmpty) body['media_ids'] = mediaIds;
    if (stickerId != null && stickerId.isNotEmpty) body['sticker_id'] = stickerId;
    final payload = await _client.postJson(
      '/api/v1/comments/$commentId/replies',
      headers: {'Idempotency-Key': idempotencyKey},
      body: body,
    );
    return _commentFromJson(payload);
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await _client.deleteJson('/api/v1/comments/$commentId');
  }

  @override
  Future<Comment> updateComment({
    required String commentId,
    required String content,
  }) async {
    final payload = await _client.patchJson(
      '/api/v1/comments/$commentId',
      body: {'content': content},
    );
    return _commentFromJson(payload);
  }

  String _newIdempotencyKey(String prefix) =>
      '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-${identityHashCode(this)}';
}

Comment _commentFromJson(Map<String, dynamic> json) {
  final authorJson = json['author'] is Map
      ? Map<String, dynamic>.from(json['author'] as Map)
      : <String, dynamic>{};
  final replyToJson = json['reply_to_user'] is Map
      ? Map<String, dynamic>.from(json['reply_to_user'] as Map)
      : <String, dynamic>{};
  final now = DateTime.now().toUtc();
  final createdAt = _date(json['created_at'], now);
  final updatedAt = _date(json['updated_at'], createdAt);
  final viewerState = json['viewer_state'] is Map
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

  return Comment(
    id: _string(json['id']),
    postId: _string(json['post_id']),
    authorId: _string(authorJson['id']),
    author: authorJson.isEmpty
        ? null
        : User(
            id: _string(authorJson['id']),
            username: _string(authorJson['username']),
            nickname: _string(authorJson['nickname']),
            avatar: _nullableString(
              authorJson['avatar'] ?? authorJson['avatar_url'],
            ),
            level: _int(authorJson['level']),
            createdAt: now,
            updatedAt: now,
          ),
    rootId: _nullableString(json['root_id']),
    parentId: _nullableString(json['parent_id']),
    replyToUserId: _nullableString(json['reply_to_user_id']),
    replyToUser: replyToJson.isEmpty
        ? null
        : User(
            id: _string(replyToJson['id']),
            username: _string(replyToJson['username']),
            nickname: _string(replyToJson['nickname']),
            avatar: _nullableString(
              replyToJson['avatar'] ?? replyToJson['avatar_url'],
            ),
            level: _int(replyToJson['level']),
            createdAt: now,
            updatedAt: now,
          ),
    content: _string(json['content']),
    media: media,
    stickerId: _nullableString(json['sticker_id']),
    likeCount: _int(json['like_count']),
    isLiked: viewerState['has_liked'] == true,
    replyCount: _int(json['reply_count']),
    publicationStatus: _enumByName(
      CommentPublicationStatus.values,
      json['publication_status'],
      CommentPublicationStatus.published,
    ),
    moderationStatus: _enumByName(
      ModerationStatus.values,
      json['moderation_status'],
      ModerationStatus.normal,
    ),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

MediaVariant? _parseVariant(dynamic raw) {
  if (raw is! Map) return null;
  final value = Map<String, dynamic>.from(raw);
  final url = _nullableString(value['url']);
  if (url == null) return null;
  return MediaVariant(
    url: url,
    width: _int(value['width']),
    height: _int(value['height']),
    sizeBytes: _nullableInt(value['size']),
    mimeType: _nullableString(value['mime_type']),
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
String? _nullableString(dynamic value) =>
    value is String && value.isNotEmpty ? value : null;
int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
int? _nullableInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value');
DateTime _date(dynamic value, DateTime fallback) =>
    value is String ? DateTime.tryParse(value) ?? fallback : fallback;

