import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/api/publish_repository.dart';
import '../data/api/ranking_repository.dart';
import '../theme/app_theme.dart';

class RankingToyIntensityOption {
  const RankingToyIntensityOption(this.value, this.label);

  final String value;
  final String label;
}

const rankingToyIntensityOptions = <RankingToyIntensityOption>[
  RankingToyIntensityOption('beginner', '慢玩入门'),
  RankingToyIntensityOption('advanced', '进阶训练'),
  RankingToyIntensityOption('high_stim', '超高刺激'),
  RankingToyIntensityOption('juice', '榨汁玩具'),
];

String rankingToyIntensityLabel(String value) {
  for (final option in rankingToyIntensityOptions) {
    if (option.value == value) return option.label;
  }
  return value;
}

class RankingToyCategoryOption {
  const RankingToyCategoryOption(this.value, this.label);

  final String value;
  final String label;
}

const rankingToyCategoryOptions = <RankingToyCategoryOption>[
  RankingToyCategoryOption('cup', '飞机杯'),
  RankingToyCategoryOption('small_hip', '小型臀模'),
  RankingToyCategoryOption('large_hip', '大型臀模'),
  RankingToyCategoryOption('half_body', '半身腿模'),
  RankingToyCategoryOption('lubricant', '润滑油'),
];

String rankingToyCategoryLabel(String value) {
  for (final option in rankingToyCategoryOptions) {
    if (option.value == value) return option.label;
  }
  return value;
}

class RankingToySubmissionScreen extends StatefulWidget {
  const RankingToySubmissionScreen({
    super.key,
    required this.rankingRepository,
    required this.publishRepository,
  });

  final RankingRepository rankingRepository;
  final PublishRepository publishRepository;

  @override
  State<RankingToySubmissionScreen> createState() =>
      _RankingToySubmissionScreenState();
}

class _RankingToySubmissionScreenState
    extends State<RankingToySubmissionScreen> {
  final nameController = TextEditingController();
  final merchantController = TextEditingController();
  final yearController = TextEditingController();
  final descriptionController = TextEditingController();
  final tagController = TextEditingController();
  String? category;
  String? intensity;
  final tags = <String>[];
  _SubmissionCover? cover;
  bool submitting = false;

  @override
  void dispose() {
    nameController.dispose();
    merchantController.dispose();
    yearController.dispose();
    descriptionController.dispose();
    tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('投稿新玩具')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
      children: [
        const Text('玩具名称 *', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('submission-name-field'),
          controller: nameController,
          enabled: !submitting,
          maxLength: 50,
          decoration: const InputDecoration(hintText: '填写玩具的完整名称'),
        ),
        const Text('品类 *', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in rankingToyCategoryOptions)
              ChoiceChip(
                key: ValueKey('submission-category-chip-${option.value}'),
                label: Text(option.label),
                selected: category == option.value,
                onSelected: submitting
                    ? null
                    : (selected) =>
                          setState(() => category = selected ? option.value : null),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('刺激度类型', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in rankingToyIntensityOptions)
              ChoiceChip(
                key: ValueKey('submission-intensity-chip-${option.value}'),
                label: Text(option.label),
                selected: intensity == option.value,
                onSelected: submitting
                    ? null
                    : (selected) => setState(
                        () => intensity = selected ? option.value : null,
                      ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('品牌', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('submission-merchant-field'),
          controller: merchantController,
          enabled: !submitting,
          maxLength: 60,
          decoration: const InputDecoration(hintText: '选填'),
        ),
        const Text('年份', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('submission-year-field'),
          controller: yearController,
          enabled: !submitting,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(hintText: '选填，如 2026'),
        ),
        const Text('标签（最多 3 个，每个 4 字内）',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags)
              InputChip(
                key: ValueKey('submission-tag-chip-$tag'),
                label: Text(tag),
                onDeleted: submitting ? null : () => setState(() => tags.remove(tag)),
              ),
          ],
        ),
        if (tags.length < 3) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('submission-tag-field'),
            controller: tagController,
            enabled: !submitting,
            maxLength: 4,
            decoration: const InputDecoration(hintText: '输入标签后点击添加'),
            onSubmitted: (_) => _addTag(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('submission-add-tag'),
              onPressed: submitting ? null : _addTag,
              child: const Text('添加标签'),
            ),
          ),
        ],
        const Text('介绍', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('submission-description-field'),
          controller: descriptionController,
          enabled: !submitting,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(hintText: '选填，简单介绍玩法与特点'),
        ),
        const Text('封面图', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _CoverPicker(
          cover: cover,
          enabled: !submitting,
          onAdd: _pickCover,
          onRemove: _removeCover,
          onRetry: () {
            final current = cover;
            if (current != null) _uploadCover(current);
          },
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('submission-submit-button'),
          onPressed: submitting ? null : _submit,
          child: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('提交投稿'),
        ),
      ],
    ),
  );

  Future<void> _pickCover() async {
    if (submitting || cover != null) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (!mounted || file == null) return;
    final addition = _SubmissionCover(file);
    setState(() => cover = addition);
    await _uploadCover(addition);
  }

  Future<void> _uploadCover(_SubmissionCover target) async {
    if (!mounted || submitting || target.uploading || target.mediaId != null) {
      return;
    }
    setState(() {
      target.uploading = true;
      target.error = null;
    });
    try {
      final bytes = target.bytes ??= await target.file.readAsBytes();
      final fileName = target.file.name.isEmpty ? 'toy-cover.jpg' : target.file.name;
      final ticket = await widget.publishRepository.requestMediaUpload(
        fileName: fileName,
        mimeType: _mimeType(fileName),
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      );
      final payload = await widget.publishRepository.uploadMedia(
        ticket: ticket,
        bytes: bytes,
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      );
      if (!mounted) return;
      setState(() {
        target.mediaId = payload['id'] is String
            ? payload['id'] as String
            : ticket.mediaId;
        target.uploading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        target.uploading = false;
        target.error = '上传失败，请重试或删除这张图片';
      });
    }
  }

  Future<void> _removeCover() async {
    final current = cover;
    if (current == null) return;
    final mediaId = current.mediaId;
    if (mediaId != null) {
      try {
        await widget.publishRepository.deleteMedia(mediaId);
      } catch (_) {
        // 远端孤儿媒体由服务端回收任务兜底，不能阻塞用户编辑表单。
      }
    }
    if (mounted) setState(() => cover = null);
  }

  void _addTag() {
    final tag = tagController.text.trim();
    if (tag.isEmpty) return;
    if (tags.contains(tag) || tags.length >= 3) return;
    setState(() {
      tags.add(tag);
      tagController.clear();
    });
  }

  Future<void> _submit() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showError('请填写玩具名称');
      return;
    }
    if (category == null) {
      _showError('请选择品类');
      return;
    }
    if (cover != null && (cover!.uploading || cover!.mediaId == null)) {
      _showError('封面仍在上传，请稍候或删除');
      return;
    }
    final yearText = yearController.text.trim();
    int? releaseYear;
    if (yearText.isNotEmpty) {
      releaseYear = int.tryParse(yearText);
      if (releaseYear == null || releaseYear < 1970 || releaseYear > 2100) {
        _showError('年份必须在 1970 到 2100 之间');
        return;
      }
    }
    setState(() => submitting = true);
    try {
      await widget.rankingRepository.submitToy(
        name: name,
        category: category!,
        merchant: merchantController.text.trim(),
        releaseYear: releaseYear,
        description: descriptionController.text.trim(),
        coverMediaId: cover?.mediaId,
        intensity: intensity,
        tags: List<String>.unmodifiable(tags),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已提交，等待管理员审核')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => submitting = false);
      _showError('投稿提交失败，请稍后重试');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SubmissionCover {
  _SubmissionCover(this.file);

  final XFile file;
  List<int>? bytes;
  String? mediaId;
  String? error;
  bool uploading = false;
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.cover,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    required this.onRetry,
  });

  final _SubmissionCover? cover;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final current = cover;
    if (current == null) {
      return InkWell(
        key: const ValueKey('submission-add-cover'),
        onTap: enabled ? onAdd : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlue,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                color: AppTheme.primary,
              ),
              SizedBox(height: 5),
              Text(
                '添加封面',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.surfaceBlue,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          if (current.uploading)
            const ColoredBox(
              color: Color(0x88000000),
              child: Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
          if (current.error != null)
            Positioned.fill(
              child: Material(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: enabled ? onRetry : null,
                  child: const Center(
                    child: Text(
                      '重试',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 2,
            top: 2,
            child: InkResponse(
              onTap: enabled ? onRemove : null,
              child: const CircleAvatar(
                radius: 11,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _mimeType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}
