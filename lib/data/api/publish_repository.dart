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
    required this.expiresAt,
  });

  final String mediaId;
  final Uri uploadUrl;
  final String uploadMethod;
  final DateTime expiresAt;
}

class ApiPublishRepository implements PublishRepository {
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
        contentType: 'application/octet-stream',
      );
      return _client.postJson(
        '/api/v1/media/${ticket.mediaId}/complete',
        body: {'size': size, 'sha256': sha256},
      );
    } on ApiException {
      rethrow;
    } catch (error) {
      throw PublishException('媒体上传失败：$error');
    }
  }
}
