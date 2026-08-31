// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/publish_controller.dart';
import '../data/composer_draft_storage.dart';
import '../data/draft_media_store/draft_media_store.dart';
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
    this.userId,
    this.publishController,
    this.enableSampleMedia = true,
    this.availableCommunities = const [],
    this.availableCommunitiesFuture,
    this.initialDraft,
    this.draftStorage,
    this.draftStorageFuture,
    this.canPublishActivity = false,
  });

  final String initialCommunityId;
  final Future<void> Function(PostDraft draft) onPublish;
  final String? userId;
  final PublishController? publishController;
  final bool enableSampleMedia;
  final List<Community> availableCommunities;
  final Future<List<Community>>? availableCommunitiesFuture;
  final ComposerDraftSnapshot? initialDraft;
  final ComposerDraftStorage? draftStorage;
  final Future<ComposerDraftStorage>? draftStorageFuture;
  final bool canPublishActivity;

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

class ComposerCategoryItem {
  const ComposerCategoryItem({
    required this.id,
    required this.label,
    required this.communityId,
    this.postType = 'normal',
    this.topic,
    this.requiresAdmin = false,
  });

  final String id;
  final String label;
  final String communityId;
  final String postType;
  final String? topic;
  final bool requiresAdmin;
}

class _PostEditorScreenState extends State<PostEditorScreen> {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  String? selectedCategoryId;
  String? topic;
  String? communityId;
  String postType = 'normal';

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
  bool _allowPop = false;
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

  List<ComposerCategoryItem> get _categoryItems {
    final list = <ComposerCategoryItem>[
      const ComposerCategoryItem(
        id: 'community-unboxing',
        label: '大型拆箱',
        communityId: 'community-unboxing',
      ),
      const ComposerCategoryItem(
        id: 'community-campus',
        label: '酱紫社区',
        communityId: 'community-campus',
      ),
      const ComposerCategoryItem(
        id: 'community-daily',
        label: '杂鱼日常',
        communityId: 'community-daily',
      ),
      const ComposerCategoryItem(
        id: 'outfit',
        label: '穿搭分享',
        communityId: 'community-campus',
        topic: 'outfit',
      ),
    ];
    if (widget.canPublishActivity) {
      list.add(
        const ComposerCategoryItem(
          id: 'activity',
          label: '活动',
          communityId: 'community-campus',
          postType: 'activity',
          requiresAdmin: true,
        ),
      );
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _draftStorage = widget.draftStorage;
    _restoringDraft =
        widget.initialDraft == null && widget.draftStorageFuture != null;
    
    _initCategorySelection();

    final draft = widget.initialDraft;
    if (draft != null) unawaited(_applyDraft(draft));
    unawaited(_loadCommunities());
    unawaited(_loadDraftStorage());
  }

  void _initCategorySelection() {
    final initialId = widget.initialCommunityId;
    if (initialId == 'community-unboxing') {
      selectedCategoryId = 'community-unboxing';
      communityId = 'community-unboxing';
    } else if (initialId == 'community-daily') {
      selectedCategoryId = 'community-daily';
      communityId = 'community-daily';
    } else {
      selectedCategoryId = 'community-campus';
      communityId = 'community-campus';
    }
  }

  void _selectCategory(ComposerCategoryItem item) {
    setState(() {
      selectedCategoryId = item.id;
      communityId = item.communityId;
      topic = item.topic;
      postType = item.postType;
      errorText = null;
    });
    _scheduleDraftSave();
  }

  Future<void> _applyDraft(ComposerDraftSnapshot draft) async {
    titleController.text = draft.title;
    bodyController.text = draft.body;
    communityId = draft.communityId ?? 'community-campus';
    topic = draft.topic;
    if (draft.topic == 'outfit') {
      selectedCategoryId = 'outfit';
    } else if (draft.communityId == 'community-unboxing') {
      selectedCategoryId = 'community-unboxing';
    } else if (draft.communityId == 'community-daily') {
      selectedCategoryId = 'community-daily';
    } else {
      selectedCategoryId = 'community-campus';
    }
    _restoredMediaIds.addAll(draft.uploadedMediaIds);
    final restoredImages = <_DraftImage>[];
    for (final draftImg in draft.images) {
      final path = draftImg.localPath.trim();
      if (path.isEmpty) continue;
      final exists = await DraftMediaStore.instance.fileExists(path);
      if (!exists) continue;
      final image = _DraftImage(file: XFile(path));
      if (draftImg.mediaId != null && draftImg.mediaId!.isNotEmpty) {
        image.mediaId = draftImg.mediaId;
        image.status = _DraftImageStatus.done;
      }
      restoredImages.add(image);
    }
    if (!mounted) return;
    setState(() {
      images
        ..clear()
        ..addAll(restoredImages);
    });
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
        _loadingCommunities = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCommunities = false;
        _communitiesLoadFailed = true;
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
        await _applyDraft(draft);
      } else if (shouldRestore == false) {
        await storage.clear();
        await DraftMediaStore.instance.clearUserDraftMedia(widget.userId ?? 'global');
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
    images: images
        .map((item) => DraftImageData(
              localPath: item.file.path,
              mediaId: item.mediaId,
            ))
        .toList(),
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
    await DraftMediaStore.instance.clearUserDraftMedia(widget.userId ?? 'global');
  }

  Future<void> _closeEditor() async {
    if (_closing || submitting) return;
    if (!_hasDraftContent) {
      _closing = true;
      _allowPop = true;
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
    _allowPop = true;
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
        type: postType,
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
        // 帖子已经成功入库
      }
      if (!mounted) return;
      _submitted = true;
      _allowPop = true;
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
    final userId = widget.userId ?? 'global';
    for (var i = 0; i < files.length && images.length + additions.length < maxImages; i++) {
      final file = files[i];
      try {
        final bytes = await file.readAsBytes();
        final savedPath = await DraftMediaStore.instance.saveDraftImage(
          originalPath: file.path,
          bytes: bytes,
          userId: userId,
          index: images.length + additions.length,
        );
        final targetFile = savedPath != null ? XFile(savedPath) : file;
        final image = _DraftImage(file: targetFile)..bytes = bytes;
        images.add(image);
        additions.add(image);
      } catch (_) {
        final image = _DraftImage(file: file);
        images.add(image);
        additions.add(image);
      }
    }
    if (mounted) setState(() {});
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
      image.bytes = null;
    }
  }

  void _deleteImage(_DraftImage image) {
    _uploadQueue.remove(image);
    image.pendingDelete = true;
    if (image.mediaId != null) _restoredMediaIds.remove(image.mediaId);
    unawaited(DraftMediaStore.instance.deleteDraftImage(image.file.path));
    setState(() {
      images.remove(image);
      errorText = null;
    });
    if (image.mediaId != null && _usesRealUpload) {
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
      canPop: _allowPop || _submitted,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_closeEditor());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFBFDFF),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFFFBFDFF),
          title: const Text(
            '发布帖子',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF17283A),
            ),
          ),
          leading: TextButton(
            onPressed: submitting ? null : () => unawaited(_closeEditor()),
            child: const Text(
              '取消',
              style: TextStyle(
                color: Color(0xFF46627E),
                fontSize: 14,
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  height: 38,
                  child: FilledButton(
                    onPressed: submitting ? null : submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(19),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: Text(
                      submitting ? '发布中…' : '发布',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
            children: [
              const Text(
                '发布到',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF51677D),
                ),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in _categoryItems)
                    _CategoryButton(
                      item: item,
                      selected: selectedCategoryId == item.id,
                      onTap: submitting || _restoringDraft
                          ? null
                          : () => _selectCategory(item),
                    ),
                ],
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    errorText!,
                    style: const TextStyle(color: Color(0xFFD95E79), fontSize: 12),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                enabled: !submitting && !_restoringDraft,
                maxLength: 40,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF17283A),
                  fontWeight: FontWeight.w600,
                ),
                onChanged: (_) {
                  setState(() {});
                  _scheduleDraftSave();
                },
                decoration: const InputDecoration(
                  hintText: '给帖子起一个清楚的标题',
                  hintStyle: TextStyle(fontSize: 15, color: Color(0xFFA8B4C1)),
                  counterText: '',
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFE5EDF5)),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFE5EDF5)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${titleController.text.length}/40',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF9AA8B6)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: bodyController,
                enabled: !submitting && !_restoringDraft,
                maxLength: 2000,
                minLines: 8,
                maxLines: 12,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF17283A),
                  height: 1.7,
                ),
                onChanged: (_) {
                  setState(() {});
                  _scheduleDraftSave();
                },
                decoration: const InputDecoration(
                  hintText: '分享你的真实体验、问题或发现……',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFFA8B4C1)),
                  counterText: '',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.only(top: 10),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${bodyController.text.length}/2000',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF9AA8B6)),
                  ),
                ),
              ),
              Container(
                height: 1,
                color: const Color(0xFFE5EDF5),
                margin: const EdgeInsets.symmetric(vertical: 14),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '图片',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF51677D),
                    ),
                  ),
                  Text(
                    _usesRealUpload
                        ? '${images.length} / $maxImages'
                        : '${selectedMedia.length} / $maxImages',
                    style: const TextStyle(
                      color: Color(0xFF7B8EA1),
                      fontSize: 11,
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
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.description_outlined, size: 13, color: Color(0xFF9CAAB8)),
                  SizedBox(width: 4),
                  Text(
                    '草稿会自动保存',
                    style: TextStyle(fontSize: 10, color: Color(0xFF9CAAB8)),
                  ),
                ],
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    errorText!,
                    style: const TextStyle(color: Color(0xFFD95E79), fontSize: 11),
                  ),
                ),
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
            label: widget.enableSampleMedia ? '添加示例图' : '添加图片',
          );
        }
      },
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ComposerCategoryItem item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF3FF) : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? const Color(0xFF8ABAFF) : const Color(0xFFDFE8F1),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF2F74C8) : const Color(0xFF5F7387),
              ),
            ),
            if (item.requiresAdmin) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF8F4),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '管理员',
                  style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF258C76),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
  const _AddImageGridTile({
    required this.onTap,
    this.count = 0,
    this.label = '添加图片',
  });

  final VoidCallback? onTap;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFE),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: const Color(0xFFCBD9E7),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_photo_alternate_outlined,
              size: 24,
              color: Color(0xFF758BA2),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF758BA2),
                fontSize: 11,
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
