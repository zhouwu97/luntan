import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 草稿中的单张图片及其已上传的 mediaId 映射。
class DraftImageData {
  const DraftImageData({
    required this.localPath,
    this.mediaId,
  });

  final String localPath;
  final String? mediaId;

  Map<String, dynamic> toJson() => {
    'local_path': localPath,
    if (mediaId != null) 'media_id': mediaId,
  };

  static DraftImageData? fromJson(Map<String, dynamic> json) {
    final localPath = json['local_path'] as String?;
    if (localPath == null || localPath.isEmpty) return null;
    return DraftImageData(
      localPath: localPath,
      mediaId: json['media_id'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DraftImageData &&
          runtimeType == other.runtimeType &&
          localPath == other.localPath &&
          mediaId == other.mediaId;

  @override
  int get hashCode => Object.hash(localPath, mediaId);
}

/// 发布编辑器的本地草稿快照。
///
/// 草稿只保存可恢复的文本、社区选择以及严格绑定的 `{localPath, mediaId}` 图片列表；
/// 发布成功或用户放弃时才清理本地文件与存储。
class ComposerDraftSnapshot {
  const ComposerDraftSnapshot({
    required this.title,
    required this.body,
    this.communityId,
    this.topic,
    this.images = const [],
    this.isPoll = false,
    this.allowMultiple = false,
    this.pollEndsAt,
    this.pollOptions = const [],
    required this.updatedAt,
  });

  final String title;
  final String body;
  final String? communityId;
  final String? topic;
  final List<DraftImageData> images;
  final bool isPoll;
  final bool allowMultiple;
  final DateTime? pollEndsAt;
  final List<String> pollOptions;
  final DateTime updatedAt;

  bool get hasContent =>
      title.trim().isNotEmpty ||
      body.trim().isNotEmpty ||
      images.isNotEmpty ||
      pollOptions.isNotEmpty;

  List<String> get localImagePaths => images.map((e) => e.localPath).toList();
  List<String> get uploadedMediaIds =>
      images.map((e) => e.mediaId).whereType<String>().toList();

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    if (communityId != null) 'community_id': communityId,
    if (topic != null) 'topic': topic,
    'images': images.map((e) => e.toJson()).toList(),
    'is_poll': isPoll,
    'allow_multiple': allowMultiple,
    if (pollEndsAt != null) 'poll_ends_at': pollEndsAt!.toUtc().toIso8601String(),
    'poll_options': pollOptions,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  static ComposerDraftSnapshot? fromJson(Map<String, dynamic> value) {
    final updatedAt = DateTime.tryParse('${value['updated_at'] ?? ''}');
    if (updatedAt == null) return null;
    final pollEndsAt = DateTime.tryParse('${value['poll_ends_at'] ?? ''}');
    List<String> readStrings(dynamic raw) => raw is List
        ? raw
              .whereType<String>()
              .where((item) => item.trim().isNotEmpty)
              .toList()
        : const <String>[];

    final parsedImages = <DraftImageData>[];
    if (value['images'] is List) {
      for (final item in value['images'] as List) {
        if (item is Map) {
          final img = DraftImageData.fromJson(Map<String, dynamic>.from(item));
          if (img != null) parsedImages.add(img);
        }
      }
    } else if (value['local_image_paths'] is List) {
      // 兼容旧版两数组结构
      final paths = readStrings(value['local_image_paths']);
      final mediaIds = readStrings(value['uploaded_media_ids']);
      for (var i = 0; i < paths.length; i++) {
        parsedImages.add(DraftImageData(
          localPath: paths[i],
          mediaId: i < mediaIds.length ? mediaIds[i] : null,
        ));
      }
    }

    return ComposerDraftSnapshot(
      title: value['title'] is String ? value['title'] as String : '',
      body: value['body'] is String ? value['body'] as String : '',
      communityId: value['community_id'] is String
          ? value['community_id'] as String
          : null,
      topic: value['topic'] is String ? value['topic'] as String : null,
      images: parsedImages,
      isPoll: value['is_poll'] is bool ? value['is_poll'] as bool : false,
      allowMultiple:
          value['allow_multiple'] is bool ? value['allow_multiple'] as bool : false,
      pollEndsAt: pollEndsAt,
      pollOptions: readStrings(value['poll_options']),
      updatedAt: updatedAt,
    );
  }
}

/// 进程内可替换的草稿存储，支持按 userId 隔离跨账号草稿。
class ComposerDraftStorage {
  ComposerDraftStorage(this._preferences, {this.userId});

  final SharedPreferences _preferences;
  final String? userId;

  static String storageKeyForUser(String? userId) {
    final clean = (userId ?? '').trim().replaceAll(RegExp(r'[^\w\-]'), '_');
    return clean.isNotEmpty
        ? 'luntan.composer.draft.v2.$clean'
        : 'luntan.composer.draft.v2.global';
  }

  String get storageKey => storageKeyForUser(userId);

  static Future<ComposerDraftStorage> create({String? userId}) async =>
      ComposerDraftStorage(await SharedPreferences.getInstance(), userId: userId);

  Future<ComposerDraftSnapshot?> load() async {
    final raw = _preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      return ComposerDraftSnapshot.fromJson(Map<String, dynamic>.from(value));
    } on FormatException {
      await clear();
      return null;
    }
  }

  Future<void> save(ComposerDraftSnapshot draft) async {
    await _preferences.setString(storageKey, jsonEncode(draft.toJson()));
  }

  Future<void> clear() async {
    await _preferences.remove(storageKey);
  }
}
