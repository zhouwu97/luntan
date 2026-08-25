// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/publish_controller.dart';
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
  });

  final bool isGameShare;
  final bool isPoll;
  final Future<void> Function(PostDraft draft) onPublish;
  final PublishController? publishController;
  final bool enableSampleMedia;

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
}

class _PostEditorDialogState extends State<PostEditorDialog> {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  final pollOptionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  ForumSection section = ForumSection.unboxing;
  List<MediaAsset> selectedMedia = const []; // mock 模式示例图
  final List<_DraftImage> images = <_DraftImage>[];
  final List<_DraftImage> _uploadQueue = <_DraftImage>[];
  int _activeUploads = 0;
  String? errorText;
  bool submitting = false;
  bool _submitted = false;

  static const int maxImages = 9;
  static const int maxConcurrentUploads = 3;
  static const int maxFileBytes = 10 * 1024 * 1024;
  static const int maxTotalBytes = 30 * 1024 * 1024;

  bool get _usesRealUpload => widget.publishController != null;

  List<MediaAsset> get sampleMedia =>
      ForumStore.seeded().posts.expand((post) => post.images).take(9).toList();

  @override
  void dispose() {
    if (!_submitted && _usesRealUpload) {
      // 用户放弃发布时清理已经上传但仍未入帖的媒体，避免服务端堆积 pending。
      for (final image in images) {
        final mediaId = image.mediaId;
        if (mediaId == null) continue;
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
    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    if (title.isEmpty) return setState(() => errorText = '请输入标题');
    if (body.isEmpty) return setState(() => errorText = '正文不能为空');
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

  Future<void> _finishSubmit({
    required String title,
    required String body,
    required List<String> pollOptions,
  }) async {
    try {
      final mediaIds = _usesRealUpload
          ? images.map((image) => image.mediaId!).toList()
          : <String>[];
      final draft = PostDraft(
        title: title,
        body: body,
        section: section,
        isGameShare: widget.isGameShare,
        isPoll: widget.isPoll,
        media: selectedMedia,
        mediaIds: mediaIds,
        pollOptions: pollOptions,
      );
      await widget.onPublish(draft);
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
      setState(() {
        image.mediaId = mediaId;
        image.status = _DraftImageStatus.done;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        image.status = _DraftImageStatus.failed;
        image.error = error is PublishException ? error.message : '图片上传失败，请重试';
      });
    } finally {
      // 图片预览会按需从 XFile 重新读取；上传完成后不把原始字节长期挂在状态树上。
      image.bytes = null;
    }
  }

  void _deleteImage(_DraftImage image) {
    if (!_usesRealUpload) return;
    if (image.status == _DraftImageStatus.uploading) return;
    _uploadQueue.remove(image);
    setState(() {
      images.remove(image);
      errorText = null;
    });
    if (image.mediaId != null) {
      widget.publishController!.deleteMedia(image.mediaId!).catchError((_) {});
    }
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
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          leading: TextButton(
            onPressed: submitting ? null : () => Navigator.of(context).pop(),
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
                onChanged: submitting
                    ? null
                    : (value) => setState(() => section = value ?? section),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                enabled: !submitting,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '给帖子起一个清楚的标题',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyController,
                enabled: !submitting,
                maxLength: 2000,
                minLines: 8,
                maxLines: 12,
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
                    onPressed: submitting
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
                                : () => setState(
                                    () =>
                                        selectedMedia = [...selectedMedia]
                                          ..removeAt(index),
                                  ),
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
                    style: const TextStyle(color: AppTheme.pink, fontSize: 12),
                  ),
                ),
            ],
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
