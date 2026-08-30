import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'draft_media_store.dart';

DraftMediaStore createDraftMediaStore() => _IoDraftMediaStore();

class _IoDraftMediaStore implements DraftMediaStore {
  String _sanitizeUserId(String userId) {
    final clean = userId.replaceAll(RegExp(r'[^\w\-]'), '_');
    return clean.isEmpty ? 'default' : clean;
  }

  Future<Directory?> _getUserDraftDirectory(String userId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory()
          .timeout(const Duration(milliseconds: 500));
      final cleanUser = _sanitizeUserId(userId);
      final dir = Directory(p.join(appDir.path, 'composer_drafts', cleanUser));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> saveDraftImage({
    required String originalPath,
    Uint8List? bytes,
    required String userId,
    required int index,
  }) async {
    try {
      final dir = await _getUserDraftDirectory(userId);
      if (dir == null) return null;

      final ext = p.extension(originalPath);
      final uniqueName =
          'draft_${DateTime.now().millisecondsSinceEpoch}_$index$ext';
      final targetPath = p.join(dir.path, uniqueName);

      if (bytes != null && bytes.isNotEmpty) {
        await File(targetPath).writeAsBytes(bytes, flush: true);
      } else {
        final src = File(originalPath);
        if (await src.exists()) {
          await src.copy(targetPath);
        } else {
          return null;
        }
      }
      return targetPath;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteDraftImage(String localPath) async {
    final path = localPath.trim();
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  Future<void> clearUserDraftMedia(String userId) async {
    try {
      final dir = await _getUserDraftDirectory(userId);
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  @override
  Future<bool> fileExists(String localPath) async {
    final path = localPath.trim();
    if (path.isEmpty) return false;
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }
}
