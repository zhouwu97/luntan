import 'dart:typed_data';

import 'draft_media_store_stub.dart'
    if (dart.library.io) 'draft_media_store_io.dart'
    if (dart.library.js_interop) 'draft_media_store_web.dart'
    if (dart.library.html) 'draft_media_store_web.dart';

abstract class DraftMediaStore {
  static DraftMediaStore instance = createDraftMediaStore();

  /// 将选中的图片文件复制/保存到按用户隔离的草稿媒体目录。
  ///
  /// 保存成功返回持久化后的绝对路径；若失败返回 null。
  Future<String?> saveDraftImage({
    required String originalPath,
    Uint8List? bytes,
    required String userId,
    required int index,
  });

  /// 删除单张草稿图片本地持久化文件。
  Future<void> deleteDraftImage(String localPath);

  /// 清空指定用户的整个草稿图片目录。
  Future<void> clearUserDraftMedia(String userId);

  /// 检查本地草稿图片文件是否存在。
  Future<bool> fileExists(String localPath);
}
