import 'dart:typed_data';

import 'draft_media_store.dart';

DraftMediaStore createDraftMediaStore() => _StubDraftMediaStore();

class _StubDraftMediaStore implements DraftMediaStore {
  @override
  Future<String?> saveDraftImage({
    required String originalPath,
    Uint8List? bytes,
    required String userId,
    required int index,
  }) async => originalPath;

  @override
  Future<void> deleteDraftImage(String localPath) async {}

  @override
  Future<void> clearUserDraftMedia(String userId) async {}

  @override
  Future<bool> fileExists(String localPath) async => true;
}
