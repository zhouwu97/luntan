import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/api/appeal_repository.dart';
import '../data/api/api_client.dart';
import '../data/api/publish_repository.dart';
import '../theme/app_theme.dart';

class AppealFormScreen extends StatefulWidget {
  const AppealFormScreen({
    super.key,
    required this.repository,
    required this.publishRepository,
    required this.action,
  });

  final AppealRepository repository;
  final PublishRepository publishRepository;
  final ModerationAction action;

  @override
  State<AppealFormScreen> createState() => _AppealFormScreenState();
}

class _AppealEvidence {
  _AppealEvidence(this.file);
  final XFile file;
  List<int>? bytes;
  String? mediaId;
  String? error;
  bool uploading = false;
}

class _AppealFormScreenState extends State<AppealFormScreen> {
  final reasonController = TextEditingController();
  final descriptionController = TextEditingController();
  final evidences = <_AppealEvidence>[];
  bool submitting = false;

  @override
  void dispose() {
    reasonController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('提交申诉')),
    body: Form(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          _SubjectCard(action: widget.action),
          const SizedBox(height: 18),
          const Text('申诉理由 *', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: reasonController,
            enabled: !submitting,
            maxLength: 100,
            decoration: const InputDecoration(hintText: '请说明你认为处理有误的原因'),
          ),
          const SizedBox(height: 8),
          const Text('补充说明', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: descriptionController,
            enabled: !submitting,
            maxLines: 5,
            maxLength: 3000,
            decoration: const InputDecoration(hintText: '可补充事实、时间线或相关背景'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '补充证据',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${evidences.length}/3',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '最多上传 3 张图片；上传失败时文字内容会保留。',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _EvidenceGrid(
            evidences: evidences,
            enabled: !submitting,
            onAdd: _pickImages,
            onRemove: _removeEvidence,
            onRetry: _uploadEvidence,
          ),
          const SizedBox(height: 24),
          FilledButton(
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
                : const Text('提交申诉'),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickImages() async {
    if (submitting || evidences.length >= 3) return;
    final files = await ImagePicker().pickMultiImage(imageQuality: 92);
    if (!mounted || files.isEmpty) return;
    final additions = files
        .take(3 - evidences.length)
        .map(_AppealEvidence.new)
        .toList();
    setState(() => evidences.addAll(additions));
    for (final evidence in additions) {
      await _uploadEvidence(evidence);
    }
  }

  Future<void> _uploadEvidence(_AppealEvidence evidence) async {
    if (!mounted ||
        submitting ||
        evidence.uploading ||
        evidence.mediaId != null) {
      return;
    }
    setState(() {
      evidence.uploading = true;
      evidence.error = null;
    });
    try {
      final bytes = evidence.bytes ??= await evidence.file.readAsBytes();
      final fileName = evidence.file.name.isEmpty
          ? 'appeal.jpg'
          : evidence.file.name;
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
        evidence.mediaId = payload['id'] is String
            ? payload['id'] as String
            : ticket.mediaId;
        evidence.uploading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        evidence.uploading = false;
        evidence.error = '上传失败，请重试或删除这张图片';
      });
    }
  }

  Future<void> _removeEvidence(_AppealEvidence evidence) async {
    if (evidence.mediaId != null) {
      try {
        await widget.publishRepository.deleteMedia(evidence.mediaId!);
      } catch (_) {
        // 远端孤儿媒体由服务端回收任务兜底，不能阻塞用户编辑正文。
      }
    }
    if (mounted) setState(() => evidences.remove(evidence));
  }

  Future<void> _submit() async {
    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      _showError('请填写申诉理由');
      return;
    }
    if (evidences.any((item) => item.uploading)) {
      _showError('图片仍在上传，请稍候');
      return;
    }
    if (evidences.any((item) => item.error != null || item.mediaId == null)) {
      _showError('请重试或删除上传失败的图片');
      return;
    }
    setState(() => submitting = true);
    try {
      await widget.repository.createAppeal(
        moderationActionId: widget.action.id,
        reason: reason,
        description: descriptionController.text.trim(),
        mediaIds: evidences.map((item) => item.mediaId!).toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => submitting = false);
      _showError(userFacingApiMessage(error, fallback: '申诉提交失败，请重试'));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.action});
  final ModerationAction action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.surfaceBlue,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '申诉对象',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          action.targetTitle.isEmpty ? '内容处理' : action.targetTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          '处理类型：${_actionLabel(action.action)}',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text('处理原因：${action.reason}', style: const TextStyle(fontSize: 13)),
      ],
    ),
  );
}

class _EvidenceGrid extends StatelessWidget {
  const _EvidenceGrid({
    required this.evidences,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    required this.onRetry,
  });
  final List<_AppealEvidence> evidences;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<_AppealEvidence> onRemove;
  final ValueChanged<_AppealEvidence> onRetry;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      ...evidences.map(
        (evidence) => SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List>(
                future: evidence.file.readAsBytes(),
                builder: (context, snapshot) => snapshot.hasData
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
              ),
              if (evidence.uploading)
                const ColoredBox(
                  color: Color(0x88000000),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              if (evidence.error != null)
                Positioned.fill(
                  child: Material(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: enabled ? () => onRetry(evidence) : null,
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
                  onTap: enabled ? () => onRemove(evidence) : null,
                  child: const CircleAvatar(
                    radius: 11,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (enabled && evidences.length < 3)
        InkWell(
          onTap: onAdd,
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
                  '添加图片',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

String _mimeType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}

String _actionLabel(String action) => switch (action) {
  'delete' => '删除内容',
  'hide' => '隐藏内容',
  'mute' => '账号禁言',
  'ban' => '账号封禁',
  _ => action.isEmpty ? '内容处理' : action,
};
