import 'dart:typed_data';

import 'draft_media_store.dart';

DraftMediaStore createDraftMediaStore() => _WebDraftMediaStore();

class _WebDraftMediaStore implements DraftMediaStore {
  @override
  Future<String?> saveDraftImage({
    required String originalPath,
    Uint8List? bytes,
    required String userId,
    required int index,
  }) async {
    // Web 平台没有本地文件系统，直接保留原始资源路径（如 blob: 或内存标识）。
    return originalPath;
  }

  @override
  Future<void> deleteDraftImage(String localPath) async {}

  @override
  Future<void> clearUserDraftMedia(String userId) async {}

  @override
  Future<bool> fileExists(String localPath) async {
    return localPath.trim().isNotEmpty;
  }
}
