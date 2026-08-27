import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 发布编辑器的本地草稿快照。
///
/// 草稿只保存可恢复的文本、社区选择和本地文件路径；已经上传的媒体 ID
/// 也会保留，发布成功后才清除。服务端仍会在帖子发布时校验媒体归属和状态。
class ComposerDraftSnapshot {
  const ComposerDraftSnapshot({
    required this.title,
    required this.body,
    this.communityId,
    this.topic,
    this.isPoll = false,
    this.pollOptions = const [],
    this.allowMultiple = false,
    this.pollEndsAt,
    this.localImagePaths = const [],
    this.uploadedMediaIds = const [],
    required this.updatedAt,
  });

  final String title;
  final String body;
  final String? communityId;
  final String? topic;
  final bool isPoll;
  final List<String> pollOptions;
  final bool allowMultiple;
  final DateTime? pollEndsAt;
  final List<String> localImagePaths;
  final List<String> uploadedMediaIds;
  final DateTime updatedAt;

  bool get hasContent =>
      title.trim().isNotEmpty ||
      body.trim().isNotEmpty ||
      pollOptions.any((item) => item.trim().isNotEmpty) ||
      localImagePaths.isNotEmpty ||
      uploadedMediaIds.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    if (communityId != null) 'community_id': communityId,
    if (topic != null) 'topic': topic,
    'is_poll': isPoll,
    'poll_options': pollOptions,
    'allow_multiple': allowMultiple,
    if (pollEndsAt != null)
      'poll_ends_at': pollEndsAt!.toUtc().toIso8601String(),
    'local_image_paths': localImagePaths,
    'uploaded_media_ids': uploadedMediaIds,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  static ComposerDraftSnapshot? fromJson(Map<String, dynamic> value) {
    final updatedAt = DateTime.tryParse('${value['updated_at'] ?? ''}');
    if (updatedAt == null) return null;
    List<String> readStrings(dynamic raw) => raw is List
        ? raw
              .whereType<String>()
              .where((item) => item.trim().isNotEmpty)
              .toList()
        : const <String>[];
    return ComposerDraftSnapshot(
      title: value['title'] is String ? value['title'] as String : '',
      body: value['body'] is String ? value['body'] as String : '',
      communityId: value['community_id'] is String
          ? value['community_id'] as String
          : null,
      topic: value['topic'] is String ? value['topic'] as String : null,
      isPoll: value['is_poll'] == true,
      pollOptions: readStrings(value['poll_options']),
      allowMultiple: value['allow_multiple'] == true,
      pollEndsAt: value['poll_ends_at'] is String
          ? DateTime.tryParse(value['poll_ends_at'] as String)
          : null,
      localImagePaths: readStrings(value['local_image_paths']),
      uploadedMediaIds: readStrings(value['uploaded_media_ids']),
      updatedAt: updatedAt,
    );
  }
}

/// 进程内可替换的草稿存储，默认使用 SharedPreferences 跨重启保存。
class ComposerDraftStorage {
  ComposerDraftStorage(this._preferences);

  static const storageKey = 'luntan.composer.draft.v1';

  final SharedPreferences _preferences;

  static Future<ComposerDraftStorage> create() async =>
      ComposerDraftStorage(await SharedPreferences.getInstance());

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
