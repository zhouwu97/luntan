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
import '../theme/app_theme.dart';
import 'post_media_preview.dart';

class ComposerSheet extends StatelessWidget {
  const ComposerSheet({
    super.key,
    required this.onCreatePost,
    required this.onCreatePoll,
    required this.onCreateGameShare,
  });

  final VoidCallback onCreatePost;
  final VoidCallback onCreatePoll;
  final VoidCallback onCreateGameShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '发布到论坛',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            '选择一种发布方式，进入完整编辑页',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PublishOption(
                icon: Icons.article_rounded,
                label: '普通帖子',
                color: AppTheme.primary,
                onTap: onCreatePost,
              ),
              _PublishOption(
                icon: Icons.poll_rounded,
                label: '发起投票',
                color: AppTheme.mint,
                onTap: onCreatePoll,
              ),
              _PublishOption(
                icon: Icons.sports_esports_outlined,
                label: '玩法分享',
                color: AppTheme.orange,
                onTap: onCreateGameShare,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PublishOption extends StatelessWidget {
  const _PublishOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Ink(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class PostEditorDialog extends StatefulWidget {
  const PostEditorDialog({
    super.key,
    required this.isGameShare,
    required this.onPublish,
    this.isPoll = false,
    this.publishController,
    this.enableSampleMedia = true,
    this.availableCommunities = const [],
    this.availableCommunitiesFuture,
    this.initialDraft,
    this.draftStorage,
    this.draftStorageFuture,
  });

  final bool isGameShare;
  final bool isPoll;
  final Future<void> Function(PostDraft draft) onPublish;
  final PublishController? publishController;
  final bool enableSampleMedia;
  final List<Community> availableCommunities;
  final Future<List<Community>>? availableCommunitiesFuture;
  final ComposerDraftSnapshot? initialDraft;
  final ComposerDraftStorage? draftStorage;
  final Future<ComposerDraftStorage>? draftStorageFuture;

  @override
  State<PostEditorDialog> createState() => _PostEditorDialogState();
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

class _PostEditorDialogState extends State<PostEditorDialog> {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  final pollOptionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  ForumSection section = ForumSection.daily;
  String? communityId;
  late final List<Community> _availableCommunities = [
    ...widget.availableCommunities,
  ];
  ComposerDraftStorage? _draftStorage;
  bool _loadingCommunities = false;
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
  bool get _isApiMode =>
      widget.availableCommunitiesFuture != null ||
      widget.publishController != null;

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

  bool get _canCreatePollSelectedCommunity =>
      _selectedCommunity?.canCreatePoll != false;

  bool get _hasDraftContent =>
      titleController.text.trim().isNotEmpty ||
      bodyController.text.trim().isNotEmpty ||
      pollOptionControllers.any(
        (controller) => controller.text.trim().isNotEmpty,
      ) ||
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
    communityId = _defaultCommunityId(_availableCommunities);
    final draft = widget.initialDraft;
    if (draft != null) _applyDraft(draft);
    unawaited(_loadCommunities());
    unawaited(_loadDraftStorage());
  }

  String? _defaultCommunityId(List<Community> communities) {
    for (final community in communities) {
      if (community.id == 'community-daily') return community.id;
    }
    return communities.isEmpty ? null : communities.first.id;
  }

  void _applyDraft(ComposerDraftSnapshot draft) {
    titleController.text = draft.title;
    bodyController.text = draft.body;
    section = ForumSection.values.firstWhere(
      (value) => value.name == draft.sectionName,
      orElse: () => ForumSection.daily,
    );
    communityId =
        _availableCommunities.any(
          (community) => community.id == draft.communityId,
        )
        ? draft.communityId
        : draft.communityId ?? _defaultCommunityId(_availableCommunities);
    for (var index = 0; index < pollOptionControllers.length; index++) {
      if (index < draft.pollOptions.length) {
        pollOptionControllers[index].text = draft.pollOptions[index];
      }
    }
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
    if (mounted) setState(() => _loadingCommunities = true);
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
        errorText = '可发布板块加载失败，请稍后重试';
      });
    }
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
        widget.publishController!.deleteMedia(mediaId).catchError((_) {});
      }
    }
    titleController.dispose();
    bodyController.dispose();
    for (final controller in pollOptionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void submit() {
    if (submitting) return;
    if (widget.availableCommunitiesFuture != null &&
        _availableCommunities.isEmpty) {
      return setState(
        () => errorText = _loadingCommunities
            ? '正在加载可发布社区，请稍候'
            : '当前没有可发布的社区，请稍后重试',
      );
    }
    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    if (title.isEmpty) return setState(() => errorText = '请输入标题');
    if (body.isEmpty) return setState(() => errorText = '正文不能为空');
    if (widget.isPoll && !_canCreatePollSelectedCommunity) {
      return setState(() => errorText = '当前社区暂不允许发起投票，请更换社区');
    }
    if (images.isNotEmpty && !_canUploadSelectedCommunity) {
      return setState(() => errorText = '当前社区暂不允许上传图片，请更换社区');
    }
    final pollOptions = pollOptionControllers
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (widget.isPoll && pollOptions.length < 2) {
      return setState(() => errorText = '投票至少需要两个选项');
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
    _finishSubmit(title: title, body: body, pollOptions: pollOptions);
  }

  ComposerDraftSnapshot _snapshot() => ComposerDraftSnapshot(
    isGameShare: widget.isGameShare,
    isPoll: widget.isPoll,
    title: titleController.text,
    body: bodyController.text,
    sectionName: section.name,
    communityId: communityId,
    pollOptions: pollOptionControllers.map((item) => item.text).toList(),
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
        section: section,
        communityId: communityId,
        isGameShare: widget.isGameShare,
        isPoll: widget.isPoll,
        media: selectedMedia,
        mediaIds: mediaIds,
        pollOptions: pollOptions,
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
        await publisher.deleteMedia(mediaId).catchError((_) {});
        return;
      }
      if (image.pendingDelete || !images.contains(image)) {
        await publisher.deleteMedia(mediaId).catchError((_) {});
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
    final title = widget.isGameShare
        ? '发布玩法分享'
        : widget.isPoll
        ? '发起投票'
        : '发布普通帖子';
    return Dialog.fullscreen(
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_closeEditor());
        },
        child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            title: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
                if (_loadingCommunities && _availableCommunities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_isApiMode)
                  if (_availableCommunities.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: communityId,
                      decoration: const InputDecoration(labelText: '发布社区'),
                      items: _availableCommunities
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name),
                            ),
                          )
                          .toList(),
                      onChanged: submitting || _restoringDraft
                          ? null
                          : (value) {
                              setState(() => communityId = value);
                              _scheduleDraftSave();
                            },
                    )
                  else
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: '发布社区',
                        suffixIcon: _loadingCommunities
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      ),
                      child: Text(
                        _loadingCommunities ? '正在加载社区…' : '暂无可用社区',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    )
                else
                  DropdownButtonFormField<ForumSection>(
                    initialValue: section,
                    decoration: const InputDecoration(labelText: '发布板块'),
                    items: ForumSection.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                        )
                        .toList(),
                    onChanged: submitting || _restoringDraft
                        ? null
                        : (value) {
                            setState(() => section = value ?? section);
                            _scheduleDraftSave();
                          },
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
                if (widget.isPoll) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '投票选项',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...pollOptionControllers.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: entry.value,
                        enabled: !submitting,
                        onChanged: (_) => _scheduleDraftSave(),
                        decoration: InputDecoration(
                          labelText: '选项 ${entry.key + 1}',
                          prefixIcon: const Icon(
                            Icons.radio_button_unchecked_rounded,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  '图片',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: submitting || !_canUploadSelectedCommunity
                          ? null
                          : (_usesRealUpload
                                ? _pickImages
                                : widget.enableSampleMedia
                                ? _addSampleImage
                                : _pickImages),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _usesRealUpload
                            ? '选择图片'
                            : widget.enableSampleMedia
                            ? '添加示例图'
                            : '选择图片',
                      ),
                    ),
                    if (!_canUploadSelectedCommunity)
                      const Expanded(
                        child: Text(
                          '当前社区不允许图片',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      _usesRealUpload
                          ? '${images.length} / $maxImages'
                          : '${selectedMedia.length} / $maxImages',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (_usesRealUpload && images.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, index) {
                        final image = images[index];
                        return _DraftImageThumb(
                          image: image,
                          onRetry: () => _enqueueUpload(image),
                          onDelete: () => _deleteImage(image),
                        );
                      },
                    ),
                  ),
                ],
                if (!_usesRealUpload && selectedMedia.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 86,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedMedia.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, index) => Stack(
                        children: [
                          SizedBox(
                            width: 86,
                            height: 86,
                            child: PostMediaPreview(
                              images: [selectedMedia[index]],
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton(
                              onPressed: submitting
                                  ? null
                                  : () {
                                      setState(
                                        () =>
                                            selectedMedia = [...selectedMedia]
                                              ..removeAt(index),
                                      );
                                      _scheduleDraftSave();
                                    },
                              icon: const Icon(
                                Icons.cancel,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      errorText!,
                      style: const TextStyle(
                        color: AppTheme.pink,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftImageThumb extends StatelessWidget {
  const _DraftImageThumb({
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
                    ? const Icon(Icons.broken_image_outlined, size: 20)
                    : const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              );
            },
          )
        : Image.memory(bytes, fit: BoxFit.cover);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          height: 68,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: preview,
              ),
              if (status == _DraftImageStatus.done)
                const Positioned(
                  right: 4,
                  top: 4,
                  child: _StatusDot(color: AppTheme.mint, icon: Icons.check),
                )
              else if (status == _DraftImageStatus.failed)
                Positioned(
                  right: 4,
                  top: 4,
                  child: GestureDetector(
                    onTap: onRetry,
                    child: const _StatusDot(
                      color: AppTheme.pink,
                      icon: Icons.refresh,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 86,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _statusLabel(status),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                iconSize: 16,
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.icon});
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    padding: const EdgeInsets.all(2),
    child: Icon(icon, color: Colors.white, size: 12),
  );
}

String _statusLabel(_DraftImageStatus status) => switch (status) {
  _DraftImageStatus.pending => '等待上传',
  _DraftImageStatus.uploading => '上传中…',
  _DraftImageStatus.done => '上传成功',
  _DraftImageStatus.failed => '上传失败',
};

String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();
