import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/controllers/publish_controller.dart';
import 'package:luntan/data/api/publish_repository.dart';

void main() {
  test('PublishController locks duplicate submits into one request', () async {
    final repository = _FakePublishRepository();
    final controller = PublishController(repository: repository);

    final first = controller.publish(
      communityId: 'c1',
      type: 'normal',
      title: '标题',
      content: '正文',
    );
    final second = controller.publish(
      communityId: 'c1',
      type: 'normal',
      title: '标题',
      content: '正文',
    );

    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(repository.createCalls, 1);
    expect(controller.isSubmitting, isFalse);
  });

  test(
    'PublishController allows an explicit retry after a failed request',
    () async {
      final repository = _FakePublishRepository()..failFirst = true;
      final controller = PublishController(repository: repository);

      await expectLater(
        controller.publish(
          communityId: 'c1',
          type: 'normal',
          title: '标题',
          content: '正文',
        ),
        throwsA(isA<PublishException>()),
      );
      expect(controller.isSubmitting, isFalse);
      await controller.publish(
        communityId: 'c1',
        type: 'normal',
        title: '标题',
        content: '正文',
      );
      expect(repository.createCalls, 2);
    },
  );
}

class _FakePublishRepository implements PublishRepository {
  int createCalls = 0;
  bool failFirst = false;

  @override
  Future<Map<String, dynamic>> createPost({
    required String communityId,
    required String type,
    required String title,
    required String content,
    required String idempotencyKey,
    List<String> mediaIds = const [],
  }) async {
    createCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (failFirst) {
      failFirst = false;
      throw const PublishException('发布失败，请检查网络后重试');
    }
    return {'id': 'p1', 'idempotency_key': idempotencyKey};
  }

  @override
  Future<MediaUploadTicket> requestMediaUpload({
    required String fileName,
    required String mimeType,
    required int size,
    required String sha256,
    int width = 0,
    int height = 0,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> uploadMedia({
    required MediaUploadTicket ticket,
    required List<int> bytes,
    required int size,
    required String sha256,
  }) => throw UnimplementedError();
}
