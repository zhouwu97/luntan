// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/publish_controller.dart';
import '../data/composer_draft_storage.dart';
import '../data/api/publish_repository.dart';
import '../data/mock_forum_data.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'post_media_preview.dart';

class PostEditorScreen extends StatefulWidget {
  const PostEditorScreen({
    super.key,
    required this.initialCommunityId,
    required this.onPublish,
    this.publishController,
    this.enableSampleMedia = true,
    this.availableCommunities = const [],
    this.availableCommunitiesFuture,
    this.initialDraft,
    this.draftStorage,
    this.draftStorageFuture,
  });

  final String initialCommunityId;
  final Future<void> Function(PostDraft draft) onPublish;
  final PublishController? publishController;
  final bool enableSampleMedia;
  final List<Community> availableCommunities;
  final Future<List<Community>>? availableCommunitiesFuture;
  final ComposerDraftSnapshot? initialDraft;
  final ComposerDraftStorage? draftStorage;
  final Future<ComposerDraftStorage>? draftStorageFuture;

  @override
  State<PostEditorScreen> createState() => _PostEditorScreenState();
}

enum _DraftImageStatus { pending, uploading, done, failed }

/// 编辑器里选中的一张待发布图片：独立跟踪字节、摘要、上传状态与失败信息。
class _DraftImage {
  _DraftImage({required this.file});
  final XFile file;
  Uint8List? bytes;
  int sizeBytes = 0;
  String? mimeType;
  int? width;
  int? height;
  String? mediaId;
  _DraftImageStatus status = _DraftImageStatus.pending;
  String? error;
  bool pendingDelete = false;
}

class _PostEditorScreenState extends State<PostEditorScreen> {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  String? topic;
  String? communityId;
  late final List<Community> _availableCommunities = [
    ...widget.availableCommunities,
  ];
  ComposerDraftStorage? _draftStorage;
  bool _loadingCommunities = false;
  bool _communitiesLoadFailed = false;
  bool _restoringDraft = false;
  List<MediaAsset> selectedMedia = const []; // mock 模式示例图
  final List<_DraftImage> images = <_DraftImage>[];
  final List<String> _restoredMediaIds = <String>[];
  final List<_DraftImage> _uploadQueue = <_DraftImage>[];
  int _activeUploads = 0;
  String? errorText;
  bool submitting = false;
  bool _submitted = false;
  bool _keepDraftMedia = false;
  bool _closing = false;
  Timer? _draftSaveTimer;

  static const int maxImages = 9;
  static const int maxConcurrentUploads = 3;
  static const int maxFileBytes = 10 * 1024 * 1024;
  static const int maxTotalBytes = 30 * 1024 * 1024;

  bool get _usesRealUpload => widget.publishController != null;

  Community? get _selectedCommunity {
    final id = communityId;
    if (id == null) return null;
    for (final community in _availableCommunities) {
      if (community.id == id) return community;
    }
    return null;
  }

  bool get _canUploadSelectedCommunity =>
      _selectedCommunity?.canUploadMedia != false;

  bool get _hasDraftContent =>
      titleController.text.trim().isNotEmpty ||
      bodyController.text.trim().isNotEmpty ||
      images.isNotEmpty ||
      selectedMedia.isNotEmpty ||
      _restoredMediaIds.isNotEmpty;

  List<MediaAsset> get sampleMedia =>
      ForumStore.seeded().posts.expand((post) => post.images).take(9).toList();

  @override
  void initState() {
    super.initState();
    _draftStorage = widget.draftStorage;
    _restoringDraft =
        widget.initialDraft == null && widget.draftStorageFuture != null;
    communityId = _resolveInitialCommunityId();
    final draft = widget.initialDraft;
    if (draft != null) _applyDraft(draft);
    unawaited(_loadCommunities());
    unawaited(_loadDraftStorage());
  }

  String? _resolveInitialCommunityId() {
    final requested = widget.initialCommunityId;
    if (requested.isNotEmpty) return requested;
    return _defaultCommunityId(_availableCommunities);
  }

  String? _defaultCommunityId(List<Community> communities) {
    for (final community in communities) {
      if (community.id == 'community-campus') return community.id;
    }
    return communities.isEmpty ? null : communities.first.id;
  }

  void _applyDraft(ComposerDraftSnapshot draft) {
    titleController.text = draft.title;
    bodyController.text = draft.body;
    communityId =
        draft.communityId ?? _defaultCommunityId(_availableCommunities);
    topic = draft.topic;
    _restoredMediaIds.addAll(draft.uploadedMediaIds);
    for (var index = 0; index < draft.localImagePaths.length; index++) {
      final path = draft.localImagePaths[index].trim();
      if (path.isEmpty) continue;
      final image = _DraftImage(file: XFile(path));
      if (index < draft.uploadedMediaIds.length) {
        image.mediaId = draft.uploadedMediaIds[index];
        image.status = _DraftImageStatus.done;
      }
      images.add(image);
    }
    if (_usesRealUpload) {
      for (final image in images) {
        if (image.status != _DraftImageStatus.done) _enqueueUpload(image);
      }
    }
  }

  Future<void> _loadCommunities() async {
    final future = widget.availableCommunitiesFuture;
    if (future == null) return;
    if (mounted) {
      setState(() {
        _loadingCommunities = true;
        _communitiesLoadFailed = false;
      });
    }
    try {
      final communities = await future;
      if (!mounted) return;
      setState(() {
        _availableCommunities
          ..clear()
          ..addAll(communities);
        if (!_availableCommunities.any((item) => item.id == communityId)) {
          communityId = _defaultCommunityId(_availableCommunities);
        }
        _loadingCommunities = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCommunities = false;
        _communitiesLoadFailed = true;
        errorText = '可发布分类加载失败，请稍后重试';
      });
    }
  }

  void _retryCommunities() {
    if (_loadingCommunities) return;
    setState(() => errorText = null);
    unawaited(_loadCommunities());
  }

  Future<void> _loadDraftStorage() async {
    final future = widget.draftStorageFuture;
    if (future == null) return;
    try {
      final storage = await future;
      if (!mounted) return;
      _draftStorage = storage;
      if (widget.initialDraft != null) return;
      final draft = await storage.load();
      if (!mounted || draft == null || !draft.hasContent) return;
      final shouldRestore = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('检测到未发布草稿'),
          content: Text('上次编辑于 ${_draftTimeLabel(draft.updatedAt)}，是否继续编辑？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('删除草稿'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('继续编辑'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (shouldRestore == true) {
        setState(() => _applyDraft(draft));
      } else if (shouldRestore == false) {
        await storage.clear();
      }
    } catch (_) {
      // 草稿存储不可用时不阻塞编辑器，发布失败仍会保留当前页面内容。
    } finally {
      if (mounted) setState(() => _restoringDraft = false);
    }
  }

  String _draftTimeLabel(DateTime value) =>
      '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    if (!_submitted && !_keepDraftMedia && _usesRealUpload) {
      // 用户放弃发布时清理已经上传但仍未入帖的媒体，避免服务端堆积 pending。
      final mediaIds = <String>{
        ..._restoredMediaIds,
        ...images.map((image) => image.mediaId).whereType<String>(),
      };
      for (final mediaId in mediaIds) {
        widget.publishController!.deleteMedia(mediaId).catchError((error) {
          if (kDebugMode) {
            debugPrint('[Composer] Failed to delete abandoned media $mediaId: $error');
          }
        });
      }
    }
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  void submit() {
    if (submitting) return;
    if (widget.availableCommunitiesFuture != null &&
        _availableCommunities.isEmpty) {
      return setState(
        () => errorText = _loadingCommunities
            ? '正在加载可发布分类，请稍候'
            : '当前没有可发布的分类，请稍后重试',
      );
    }
    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    if (title.isEmpty) return setState(() => errorText = '请输入标题');
    if (body.isEmpty) return setState(() => errorText = '正文不能为空');
    if (images.isNotEmpty && !_canUploadSelectedCommunity) {
      return setState(() => errorText = '当前社区暂不允许上传图片，请更换社区');
    }
    if (_usesRealUpload &&
        images.any((image) => image.status != _DraftImageStatus.done)) {
      final failed = images.any(
        (image) => image.status == _DraftImageStatus.failed,
      );
      return setState(
        () => errorText = failed ? '有图片上传失败，请重试或删除后再发布' : '图片仍在上传，请稍候',
      );
    }
    setState(() => submitting = true);
    _finishSubmit(title: title, body: body, pollOptions: const []);
  }

  ComposerDraftSnapshot _snapshot() => ComposerDraftSnapshot(
    title: titleController.text,
    body: bodyController.text,
    communityId: communityId,
    topic: topic,
    isPoll: false,
    pollOptions: const [],
    allowMultiple: false,
    pollEndsAt: null,
    localImagePaths: images.map((item) => item.file.path).toList(),
    uploadedMediaIds: <String>{
      ..._restoredMediaIds,
      ...images.map((item) => item.mediaId).whereType<String>(),
    }.toList(),
    updatedAt: DateTime.now().toUtc(),
  );

  void _scheduleDraftSave() {
    if (_draftStorage == null || _submitted) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_saveDraftNow());
    });
  }

  Future<void> _saveDraftNow() async {
    final storage = _draftStorage;
    if (storage == null) return;
    if (!_hasDraftContent) {
      await storage.clear();
      return;
    }
    await storage.save(_snapshot());
  }

  Future<void> _clearDraft() async {
    _draftSaveTimer?.cancel();
    await _draftStorage?.clear();
  }

  Future<void> _closeEditor() async {
    if (_closing || submitting) return;
    if (!_hasDraftContent) {
      _closing = true;
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存当前草稿？'),
        content: const Text('离开编辑器后，已填写内容和已上传媒体可以在下次继续编辑。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'continue'),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('保存并退出'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'continue') return;
    _closing = true;
    if (choice == 'save') {
      _keepDraftMedia = true;
      try {
        await _saveDraftNow();
      } catch (_) {
        _keepDraftMedia = false;
        _closing = false;
        if (mounted) setState(() => errorText = '草稿保存失败，请检查设备存储后重试');
        return;
      }
    } else {
      await _clearDraft();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _finishSubmit({
    required String title,
    required String body,
    required List<String> pollOptions,
  }) async {
    try {
      final mediaIds = _usesRealUpload
          ? <String>{
              ..._restoredMediaIds,
              ...images.map((image) => image.mediaId).whereType<String>(),
            }.toList()
          : <String>[];
      final draft = PostDraft(
        title: title,
        body: body,
        section: _sectionForCommunityId(communityId),
        communityId: communityId,
        media: selectedMedia,
        mediaIds: mediaIds,
        topic: topic,
        isPoll: false,
        pollOptions: const [],
        allowMultiple: false,
        pollEndsAt: null,
      );
      await widget.onPublish(draft);
      if (!mounted) return;
      try {
        await _clearDraft();
      } catch (_) {
        // 帖子已经成功入库；本地草稿清理失败不会把成功结果伪装成发布失败。
      }
      if (!mounted) return;
      _submitted = true;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        errorText = error is PublishException ? error.message : '发布失败，请检查网络后重试';
      });
    }
  }

  Future<void> _pickImages() async {
    if (submitting || images.length >= maxImages) return;
    final files = await ImagePicker().pickMultiImage(imageQuality: 92);
    if (!mounted || files.isEmpty) return;
    final additions = <_DraftImage>[];
    setState(() {
      for (final file in files.take(maxImages - images.length)) {
        final image = _DraftImage(file: file);
        images.add(image);
        additions.add(image);
      }
    });
    _scheduleDraftSave();
    for (final image in additions) {
      _enqueueUpload(image);
    }
  }

  void _enqueueUpload(_DraftImage image) {
    if (!_uploadQueue.contains(image)) _uploadQueue.add(image);
    _pumpUploads();
  }

  void _pumpUploads() {
    while (mounted &&
        _activeUploads < maxConcurrentUploads &&
        _uploadQueue.isNotEmpty) {
      final image = _uploadQueue.removeAt(0);
      if (!images.contains(image) ||
          image.status == _DraftImageStatus.done ||
          image.status == _DraftImageStatus.uploading) {
        continue;
      }
      _activeUploads++;
      _upload(image).whenComplete(() {
        _activeUploads--;
        _pumpUploads();
      });
    }
  }

  Future<void> _upload(_DraftImage image) async {
    final publisher = widget.publishController;
    if (publisher == null) return;
    if (image.status == _DraftImageStatus.done ||
        image.status == _DraftImageStatus.uploading) {
      return;
    }
    setState(() {
      image.status = _DraftImageStatus.uploading;
      image.error = null;
    });
    try {
      final bytes = image.bytes = await image.file.readAsBytes();
      _assertValidImage(image.file.name, bytes);
      image.sizeBytes = bytes.length;
      final totalBytes = images.fold<int>(
        0,
        (sum, item) => sum + item.sizeBytes,
      );
      if (totalBytes > maxTotalBytes) {
        throw const PublishException('图片总量不能超过 30 MB');
      }
      // 摘要计算放到 isolate，避免大图在编辑器 UI isolate 中阻塞掉帧。
      final digest = await compute(_sha256Hex, bytes);
      final mediaId = await publisher.uploadMedia(
        fileName: image.file.name,
        mimeType: image.mimeType ??= _mimeType(image.file.name),
        bytes: bytes,
        sha256: digest,
        width: image.width ?? 0,
        height: image.height ?? 0,
      );
      if (!mounted) {
        // 取消编辑器后，上传协程仍可能晚于 dispose 返回 media_id；
        // 此时页面已无法把媒体挂到帖子，立即回收避免孤儿媒体。
        await publisher.deleteMedia(mediaId).catchError((error) {
          if (kDebugMode) {
            debugPrint('[Composer] Failed to delete orphan media after unmount: $error');
          }
        });
        return;
      }
      if (image.pendingDelete || !images.contains(image)) {
        await publisher.deleteMedia(mediaId).catchError((error) {
          if (kDebugMode) {
            debugPrint('[Composer] Failed to delete removed media $mediaId: $error');
          }
        });
        return;
      }
      setState(() {
        image.mediaId = mediaId;
        image.status = _DraftImageStatus.done;
      });
      _scheduleDraftSave();
    } catch (error) {
      if (!mounted || image.pendingDelete || !images.contains(image)) return;
      setState(() {
        image.status = _DraftImageStatus.failed;
        image.error = error is PublishException ? error.message : '图片上传失败，请重试';
      });
      _scheduleDraftSave();
    } finally {
      // 图片预览会按需从 XFile 重新读取；上传完成后不把原始字节长期挂在状态树上。
      image.bytes = null;
    }
  }

  void _deleteImage(_DraftImage image) {
    if (!_usesRealUpload) return;
    _uploadQueue.remove(image);
    image.pendingDelete = true;
    if (image.mediaId != null) _restoredMediaIds.remove(image.mediaId);
    setState(() {
      images.remove(image);
      errorText = null;
    });
    if (image.mediaId != null) {
      widget.publishController!.deleteMedia(image.mediaId!).catchError((_) {});
    }
    _scheduleDraftSave();
  }

  void _assertValidImage(String fileName, List<int> bytes) {
    if (bytes.length > maxFileBytes) {
      throw const PublishException('单张图片不能超过 10 MB');
    }
    final extension = fileName.toLowerCase();
    if (!(extension.endsWith('.jpg') ||
        extension.endsWith('.jpeg') ||
        extension.endsWith('.png') ||
        extension.endsWith('.webp'))) {
      throw const PublishException('仅支持 JPG、PNG、WEBP 图片');
    }
  }

  Future<void> _addSampleImage() async {
    final additions = [...sampleMedia.take(maxImages - selectedMedia.length)];
    setState(() => selectedMedia = [...selectedMedia, ...additions]);
    _scheduleDraftSave();
  }

  String _mimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_closeEditor());
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text(
            '发布帖子',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          leading: TextButton(
            onPressed: submitting ? null : () => unawaited(_closeEditor()),
            child: const Text('取消'),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton(
                onPressed: submitting ? null : submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                ),
                child: Text(submitting ? '发布中…' : '发布'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 30),
            children: [
              _CommunitySelector(
                communities: _availableCommunities,
                selectedCommunityId: communityId,
                onChanged: (value) {
                  setState(() => communityId = value);
                  _scheduleDraftSave();
                },
                enabled: !submitting && !_restoringDraft,
                loading: _loadingCommunities,
                loadFailed: _communitiesLoadFailed,
                onRetry: _retryCommunities,
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    errorText!,
                    style: const TextStyle(color: AppTheme.pink, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                enabled: !submitting && !_restoringDraft,
                maxLength: 40,
                onChanged: (_) => _scheduleDraftSave(),
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '给帖子起一个清楚的标题',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyController,
                enabled: !submitting && !_restoringDraft,
                maxLength: 2000,
                minLines: 8,
                maxLines: 12,
                onChanged: (_) => _scheduleDraftSave(),
                decoration: const InputDecoration(
                  labelText: '正文',
                  hintText: '分享你的真实体验、问题或发现…',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: topic,
                decoration: const InputDecoration(
                  labelText: '内容主题（可选）',
                  helperText: '选择后，内容会进入对应主题页；不再按是否有图片猜测',
                ),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('不设置')),
                  DropdownMenuItem<String?>(
                    value: 'outfit',
                    child: Text('穿搭分享'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'activity',
                    child: Text('活动'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'game_share',
                    child: Text('玩法分享'),
                  ),
                ],
                onChanged: submitting
                    ? null
                    : (value) {
                        setState(() => topic = value);
                        _scheduleDraftSave();
                      },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '图片',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _usesRealUpload
                        ? '${images.length} / $maxImages'
                        : '${selectedMedia.length} / $maxImages',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (!_canUploadSelectedCommunity)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '当前社区暂不允许上传图片',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 10),
              _buildImagesGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagesGrid() {
    final count = _usesRealUpload
        ? (images.length < maxImages && _canUploadSelectedCommunity
            ? images.length + 1
            : images.length)
        : (selectedMedia.length < maxImages
            ? selectedMedia.length + 1
            : selectedMedia.length);

    if (count == 0) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        if (_usesRealUpload) {
          if (index < images.length) {
            final image = images[index];
            return _DraftImageGridThumb(
              image: image,
              onRetry: () => _enqueueUpload(image),
              onDelete: () => _deleteImage(image),
            );
          }
          return _AddImageGridTile(
            onTap: submitting || !_canUploadSelectedCommunity ? null : _pickImages,
            count: images.length,
          );
        } else {
          if (index < selectedMedia.length) {
            return _SampleMediaGridThumb(
              media: selectedMedia[index],
              onDelete: () {
                setState(
                  () => selectedMedia = [...selectedMedia]..removeAt(index),
                );
                _scheduleDraftSave();
              },
            );
          }
          return _AddImageGridTile(
            onTap: submitting
                ? null
                : (widget.enableSampleMedia ? _addSampleImage : _pickImages),
            count: selectedMedia.length,
          );
        }
      },
    );
  }
}

/// 发帖分类选择器，视觉与首页三段 Tab 一致：三个正式板块（大型拆箱 /
/// 酱紫社区 / 杂鱼日常），不再提供“发布社区”下拉框。
class _CommunitySelector extends StatelessWidget {
  const _CommunitySelector({
    required this.communities,
    required this.selectedCommunityId,
    required this.onChanged,
    required this.enabled,
    required this.loading,
    required this.loadFailed,
    required this.onRetry,
  });

  final List<Community> communities;
  final String? selectedCommunityId;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool loading;
  final bool loadFailed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlue,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.border),
      ),
      child: communities.isEmpty
          ? loading
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          loadFailed ? '分类加载失败' : '暂无可用分类',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (loadFailed)
                        InkWell(
                          onTap: onRetry,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '重试',
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
          : Row(
              children: communities
                  .map(
                    (community) => Expanded(
                      child: _CommunitySegment(
                        label: community.name,
                        active: selectedCommunityId == community.id,
                        onTap: enabled ? () => onChanged(community.id) : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _CommunitySegment extends StatelessWidget {
  const _CommunitySegment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.normal),
        curve: AppMotion.emphasized,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _DraftImageGridThumb extends StatelessWidget {
  const _DraftImageGridThumb({
    required this.image,
    required this.onRetry,
    required this.onDelete,
  });

  final _DraftImage image;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bytes = image.bytes;
    final status = image.status;
    final Widget preview = bytes == null
        ? FutureBuilder<Uint8List>(
            future: image.file.readAsBytes(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Image.memory(snapshot.data!, fit: BoxFit.cover);
              }
              return Container(
                color: AppTheme.surfaceBlue,
                alignment: Alignment.center,
                child: snapshot.hasError
                    ? const Icon(
                        Icons.broken_image_outlined,
                        size: 22,
                        color: AppTheme.textSecondary,
                      )
                    : const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              );
            },
          )
        : Image.memory(bytes, fit: BoxFit.cover);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          preview,
          if (status == _DraftImageStatus.uploading)
            Container(
              color: Colors.black38,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            )
          else if (status == _DraftImageStatus.failed)
            GestureDetector(
              onTap: onRetry,
              child: Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.refresh, color: Colors.white, size: 22),
                    SizedBox(height: 2),
                    Text(
                      '重试',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            right: 4,
            top: 4,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddImageGridTile extends StatelessWidget {
  const _AddImageGridTile({required this.onTap, this.count = 0});

  final VoidCallback? onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlue,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 28,
              color: AppTheme.textSecondary,
            ),
            SizedBox(height: 4),
            Text(
              '添加图片',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SampleMediaGridThumb extends StatelessWidget {
  const _SampleMediaGridThumb({
    required this.media,
    required this.onDelete,
  });

  final MediaAsset media;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PostMediaPreview(
            images: [media],
            mode: PostMediaPreviewMode.detail,
          ),
          Positioned(
            right: 4,
            top: 4,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

ForumSection _sectionForCommunityId(String? communityId) =>
    switch (communityId) {
      'community-campus' => ForumSection.community,
      'community-daily' => ForumSection.daily,
      _ => ForumSection.unboxing,
    };
