import 'package:flutter/foundation.dart';

import '../data/api/publish_repository.dart';

class PublishController extends ChangeNotifier {
  PublishController({required PublishRepository repository})
    : _repository = repository;

  final PublishRepository _repository;
  Future<Map<String, dynamic>>? _inFlight;
  String? _pendingIdempotencyKey;
  bool isSubmitting = false;
  String? errorMessage;

  Future<Map<String, dynamic>> publish({
    required String communityId,
    required String type,
    required String title,
    required String content,
    List<String> mediaIds = const [],
  }) {
    final running = _inFlight;
    if (running != null) return running;
    final idempotencyKey = _pendingIdempotencyKey ??= _newIdempotencyKey();
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    late final Future<Map<String, dynamic>> future;
    future =
        _runPublish(
          communityId: communityId,
          type: type,
          title: title,
          content: content,
          mediaIds: mediaIds,
          idempotencyKey: idempotencyKey,
        ).whenComplete(() {
          if (identical(_inFlight, future)) _inFlight = null;
        });
    _inFlight = future;
    return future;
  }

  Future<Map<String, dynamic>> _runPublish({
    required String communityId,
    required String type,
    required String title,
    required String content,
    required List<String> mediaIds,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _repository.createPost(
        communityId: communityId,
        type: type,
        title: title,
        content: content,
        mediaIds: mediaIds,
        idempotencyKey: idempotencyKey,
      );
      _pendingIdempotencyKey = null;
      return response;
    } catch (error) {
      errorMessage = error is PublishException ? error.message : '发布失败，请稍后重试';
      rethrow;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  String _newIdempotencyKey() =>
      'post-${DateTime.now().toUtc().microsecondsSinceEpoch}-${identityHashCode(this)}';
}
