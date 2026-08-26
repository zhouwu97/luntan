import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 发布编辑器的本地草稿快照。
///
/// 草稿只保存可恢复的文本、社区选择和本地文件路径；已经上传的媒体 ID
/// 也会保留，发布成功后才清除。服务端仍会在帖子发布时校验媒体归属和状态。
class ComposerDraftSnapshot {
  const ComposerDraftSnapshot({
    required this.isGameShare,
    required this.isPoll,
    required this.title,
    required this.body,
    required this.sectionName,
    this.communityId,
    this.pollOptions = const [],
    this.allowMultiple = false,
    this.pollEndsAt,
    this.localImagePaths = const [],
    this.uploadedMediaIds = const [],
    required this.updatedAt,
  });

  final bool isGameShare;
  final bool isPoll;
  final String title;
  final String body;
  final String sectionName;
  final String? communityId;
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
    'is_game_share': isGameShare,
    'is_poll': isPoll,
    'title': title,
    'body': body,
    'section_name': sectionName,
    if (communityId != null) 'community_id': communityId,
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
    final pollEndsAt = value['poll_ends_at'] == null
        ? null
        : DateTime.tryParse('${value['poll_ends_at']}');
    return ComposerDraftSnapshot(
      isGameShare: value['is_game_share'] == true,
      isPoll: value['is_poll'] == true,
      title: value['title'] is String ? value['title'] as String : '',
      body: value['body'] is String ? value['body'] as String : '',
      sectionName: value['section_name'] is String
          ? value['section_name'] as String
          : 'unboxing',
      communityId: value['community_id'] is String
          ? value['community_id'] as String
          : null,
      pollOptions: readStrings(value['poll_options']),
      allowMultiple: value['allow_multiple'] == true,
      pollEndsAt: pollEndsAt,
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
