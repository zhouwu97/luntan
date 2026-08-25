import 'api_client.dart';

abstract interface class PublishRepository {
  Future<Map<String, dynamic>> createPost({
    required String communityId,
    required String type,
    required String title,
    required String content,
    required String idempotencyKey,
    List<String> mediaIds,
  });

  Future<MediaUploadTicket> requestMediaUpload({
    required String fileName,
    required String mimeType,
    required int size,
    required String sha256,
    int width,
    int height,
  });

  Future<Map<String, dynamic>> uploadMedia({
    required MediaUploadTicket ticket,
    required List<int> bytes,
    required int size,
    required String sha256,
  });

  /// 清理尚未关联帖子的已上传媒体（放弃发布或单图删除）。
  Future<void> deleteMedia(String mediaId);
}

abstract interface class PollPublishRepository {
  Future<Map<String, dynamic>> createPoll({
    required String postId,
    required String question,
    required List<String> options,
    bool allowMultiple,
    DateTime? endsAt,
  });
}

/// 投票帖子必须在一次服务端事务中完成帖子、投票和选项写入。
abstract interface class AtomicPollPublishRepository {
  Future<Map<String, dynamic>> createPollPost({
    required String communityId,
    required String title,
    required String content,
    required String idempotencyKey,
    required List<String> options,
    bool allowMultiple,
    DateTime? endsAt,
    List<String> mediaIds,
  });
}

class PublishException implements Exception {
  const PublishException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MediaUploadTicket {
  const MediaUploadTicket({
    required this.mediaId,
    required this.uploadUrl,
    required this.uploadMethod,
    required this.mimeType,
    required this.expiresAt,
  });

  final String mediaId;
  final Uri uploadUrl;
  final String uploadMethod;
  final String mimeType;
  final DateTime expiresAt;
}

class ApiPublishRepository
    implements
        PublishRepository,
        PollPublishRepository,
        AtomicPollPublishRepository {
  ApiPublishRepository(this._client);

  final ApiClient _client;

  @override
  Future<Map<String, dynamic>> createPost({
    required String communityId,
    required String type,
    required String title,
    required String content,
    required String idempotencyKey,
    List<String> mediaIds = const [],
  }) {
    return _client.postJson(
      '/api/v1/posts',
      headers: {'Idempotency-Key': idempotencyKey},
      body: {
        'community_id': communityId,
        'type': type,
        'title': title,
        'content': content,
        if (mediaIds.isNotEmpty) 'media_ids': mediaIds,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> createPoll({
    required String postId,
    required String question,
    required List<String> options,
    bool allowMultiple = false,
    DateTime? endsAt,
  }) => _client.postJson(
    '/api/v1/posts/$postId/poll',
    body: {
      'question': question,
      'options': options,
      'allow_multiple': allowMultiple,
      if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
    },
  );

  @override
  Future<Map<String, dynamic>> createPollPost({
    required String communityId,
    required String title,
    required String content,
    required String idempotencyKey,
    required List<String> options,
    bool allowMultiple = false,
    DateTime? endsAt,
    List<String> mediaIds = const [],
  }) => _client.postJson(
    '/api/v1/posts',
    headers: {'Idempotency-Key': idempotencyKey},
    body: {
      'community_id': communityId,
      'type': 'poll',
      'title': title,
      'content': content,
      if (mediaIds.isNotEmpty) 'media_ids': mediaIds,
      'poll': {
        'question': title,
        'options': options,
        'allow_multiple': allowMultiple,
        if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
      },
    },
  );

  @override
  Future<MediaUploadTicket> requestMediaUpload({
    required String fileName,
    required String mimeType,
    required int size,
    required String sha256,
    int width = 0,
    int height = 0,
  }) async {
    final payload = await _client.postJson(
      '/api/v1/media/upload-token',
      body: {
        'file_name': fileName,
        'mime_type': mimeType,
        'size': size,
        'sha256': sha256,
        'width': width,
        'height': height,
      },
      requestTimeout: _client.uploadTimeout,
    );
    final mediaId = payload['media_id'];
    final uploadUrl = payload['upload_url'];
    final uploadMethod = payload['upload_method'];
    final expiresAt = DateTime.tryParse('${payload['expires_at']}');
    if (mediaId is! String ||
        mediaId.isEmpty ||
        uploadUrl is! String ||
        Uri.tryParse(uploadUrl) == null ||
        uploadMethod is! String ||
        expiresAt == null) {
      throw const PublishException('媒体上传凭证格式错误');
    }
    return MediaUploadTicket(
      mediaId: mediaId,
      uploadUrl: Uri.parse(uploadUrl),
      uploadMethod: uploadMethod,
      mimeType: mimeType,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<Map<String, dynamic>> uploadMedia({
    required MediaUploadTicket ticket,
    required List<int> bytes,
    required int size,
    required String sha256,
  }) async {
    if (ticket.uploadMethod.toUpperCase() != 'PUT') {
      throw const PublishException('暂不支持该媒体上传方式');
    }
    try {
      await _client.uploadBytes(
        ticket.uploadUrl,
        bytes,
        contentType: ticket.mimeType,
      );
      return await _client.postJson(
        '/api/v1/media/${ticket.mediaId}/complete',
        body: {'size': size, 'sha256': sha256},
        requestTimeout: _client.uploadTimeout,
      );
    } on ApiException {
      await _deleteMediaSilently(ticket.mediaId);
      rethrow;
    } catch (error) {
      await _deleteMediaSilently(ticket.mediaId);
      throw PublishException('媒体上传失败：$error');
    }
  }

  Future<void> _deleteMediaSilently(String mediaId) async {
    try {
      await deleteMedia(mediaId);
    } catch (_) {
      // 完成请求可能已经成功但响应丢失，此时服务端会拒绝删除已挂帖媒体。
      // 清理失败不能覆盖原始上传错误，后续由媒体回收任务兜底。
    }
  }

  @override
  Future<void> deleteMedia(String mediaId) async {
    await _client.deleteJson('/api/v1/media/$mediaId');
  }
}
