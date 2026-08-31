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

  InputDecoration _inputDecoration({
    required String hintText,
  }) => InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA1AFBC)),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFDFE8F2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF8AB8F7), width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFEAF0F6)),
    ),
    counterStyle: const TextStyle(fontSize: 10, color: Color(0xFF9AA8B6)),
  );

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF5E7285),
        letterSpacing: 0.2,
      ),
    ),
  );

  Widget _buildFieldLabel(
    String label, {
    bool isRequired = false,
    String? note,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF52687B),
          ),
        ),
        if (isRequired)
          const Text(
            ' *',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5A9EFF),
            ),
          ),
        if (note != null) ...[
          const SizedBox(width: 6),
          Text(
            note,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF8A9BAC),
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _buildChoiceButton({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEDF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF78AEF2) : const Color(0xFFC9D4DF),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFF2B6DBA) : const Color(0xFF34495D),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('投稿新玩具')),
    body: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
            children: [
              // 1. 基本信息
              _buildSectionTitle('基本信息'),
              _buildFieldLabel('玩具名称', isRequired: true),
              TextField(
                key: const ValueKey('submission-name-field'),
                controller: nameController,
                enabled: !submitting,
                maxLength: 50,
                decoration: _inputDecoration(hintText: '填写玩具的完整名称'),
              ),
              const SizedBox(height: 10),
              _buildFieldLabel('品牌与年份'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('submission-merchant-field'),
                      controller: merchantController,
                      enabled: !submitting,
                      maxLength: 60,
                      decoration: _inputDecoration(hintText: '品牌（选填）'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      key: const ValueKey('submission-year-field'),
                      controller: yearController,
                      enabled: !submitting,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: _inputDecoration(hintText: '年份'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. 分类
              _buildSectionTitle('分类'),
              _buildFieldLabel('品类', isRequired: true),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in rankingToyCategoryOptions)
                    _buildChoiceButton(
                      key: ValueKey('submission-category-chip-${option.value}'),
                      label: option.label,
                      selected: category == option.value,
                      onTap: submitting
                          ? null
                          : () => setState(
                                () => category =
                                    category == option.value ? null : option.value,
                              ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _buildFieldLabel('刺激度类型'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in rankingToyIntensityOptions)
                    _buildChoiceButton(
                      key: ValueKey('submission-intensity-chip-${option.value}'),
                      label: option.label,
                      selected: intensity == option.value,
                      onTap: submitting
                          ? null
                          : () => setState(
                                () => intensity =
                                    intensity == option.value ? null : option.value,
                              ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. 内容补充
              _buildSectionTitle('内容补充'),
              _buildFieldLabel('标签', note: '最多 3 个，每个 4 字'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('submission-tag-field'),
                      controller: tagController,
                      enabled: !submitting && tags.length < 3,
                      maxLength: 4,
                      decoration: _inputDecoration(
                        hintText: tags.length < 3 ? '输入标签' : '已达到 3 个上限',
                      ),
                      onSubmitted: (_) => _addTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      key: const ValueKey('submission-add-tag'),
                      onPressed: submitting || tags.length >= 3 ? null : _addTag,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFBFD3EA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        foregroundColor: const Color(0xFF2B6DBA),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text(
                        '添加',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final tag in tags)
                      Container(
                        key: ValueKey('submission-tag-chip-$tag'),
                        padding: const EdgeInsets.fromLTRB(9, 4, 4, 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FBFE),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: const Color(0xFFD7E3EE)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF4A6277),
                              ),
                            ),
                            const SizedBox(width: 3),
                            if (!submitting)
                              InkWell(
                                onTap: () => setState(() => tags.remove(tag)),
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Color(0xFF8497A8),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              _buildFieldLabel('介绍'),
              TextField(
                key: const ValueKey('submission-description-field'),
                controller: descriptionController,
                enabled: !submitting,
                maxLines: 4,
                maxLength: 2000,
                decoration: _inputDecoration(hintText: '简单介绍玩法与特点（选填）'),
              ),
              const SizedBox(height: 10),
              _buildFieldLabel('封面图'),
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
              const SizedBox(height: 12),
            ],
          ),
        ),
        // 底部固定提交按钮
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
          decoration: const BoxDecoration(
            color: AppTheme.background,
            border: Border(top: BorderSide(color: Color(0xFFEAF0F6))),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                key: const ValueKey('submission-submit-button'),
                onPressed: submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '提交投稿',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
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
    final coverWidget = current == null
        ? InkWell(
            key: const ValueKey('submission-add-cover'),
            onTap: enabled ? onAdd : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFB9CDDF),
                  width: 1,
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 21,
                    color: Color(0xFF5C7890),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '添加封面',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF5C7890),
                    ),
                  ),
                ],
              ),
            ),
          )
        : SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBlue,
                    borderRadius: BorderRadius.circular(10),
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
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: enabled ? onRetry : null,
                        child: const Center(
                          child: Text(
                            '重试',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
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
                      radius: 10,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ],
            ),
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        coverWidget,
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            '选填，建议使用清晰方图或竖图。\n上传失败时可重试或移除。',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF7C8FA1),
              height: 1.5,
            ),
          ),
        ),
      ],
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
