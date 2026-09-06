import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:luntan/data/api/publish_repository.dart';
import 'package:luntan/services/media_upload_service.dart';

void main() {
  test('GIF 上传预处理保留动画帧与原始编码', () async {
    final animation = img.Image(width: 2, height: 2)..frameDuration = 80;
    animation.addFrame(img.Image(width: 2, height: 2)..frameDuration = 120);
    final bytes = img.encodeGif(animation);
    expect(img.decodeGif(bytes)?.numFrames, 2);

    final prepared = await MediaUploadService.prepareImage(
      XFile.fromData(bytes, name: 'meme.gif'),
    );

    expect(prepared.mimeType, 'image/gif');
    expect(prepared.fileName, 'image.gif');
    expect(prepared.bytes, bytes);
    expect(img.decodeGif(prepared.bytes)?.numFrames, 2);
  });

  test('按文件内容识别 PNG，携带尺寸和 SHA-256', () async {
    final source = img.Image(width: 2, height: 3);
    final bytes = img.encodePng(source);
    final prepared = await MediaUploadService.prepareImage(
      XFile.fromData(bytes, name: 'photo.jpg'),
    );

    expect(prepared.mimeType, 'image/png');
    expect(prepared.fileName, 'image.png');
    expect(prepared.width, 2);
    expect(prepared.height, 3);
    expect(prepared.sha256, hasLength(64));
  });

  test('批量上传中途失败会清理已完成的媒体', () async {
    final repository = _FakePublishRepository();
    final valid = img.encodePng(img.Image(width: 2, height: 2));
    final service = MediaUploadService(repository);

    await expectLater(
      service.uploadImages([
        XFile.fromData(valid, name: 'ok.png'),
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'bad.jpg'),
      ]),
      throwsA(isA<PublishException>()),
    );

    expect(repository.deletedMediaIds, ['media-1']);
  });
}

class _FakePublishRepository implements PublishRepository {
  final deletedMediaIds = <String>[];

  @override
  Future<Map<String, dynamic>> createPost({
    required String communityId,
    required String type,
    required String title,
    required String content,
    required String idempotencyKey,
    List<String> mediaIds = const [],
    String? topic,
  }) => throw UnimplementedError();

  @override
  Future<MediaUploadTicket> requestMediaUpload({
    required String fileName,
    required String mimeType,
    required int size,
    required String sha256,
    int width = 0,
    int height = 0,
  }) async => MediaUploadTicket(
    mediaId: 'media-1',
    uploadUrl: Uri.parse('https://upload.invalid/media-1'),
    uploadMethod: 'PUT',
    mimeType: mimeType,
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );

  @override
  Future<Map<String, dynamic>> uploadMedia({
    required MediaUploadTicket ticket,
    required List<int> bytes,
    required int size,
    required String sha256,
  }) async => <String, dynamic>{'id': ticket.mediaId};

  @override
  Future<Map<String, dynamic>> completeMedia({
    required String mediaId,
    required int size,
    required String sha256,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteMedia(String mediaId) async =>
      deletedMediaIds.add(mediaId);
}
