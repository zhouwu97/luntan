import 'package:flutter/material.dart';

import '../data/api/appeal_repository.dart';
import '../data/api/api_client.dart';
import '../theme/app_theme.dart';
import '../theme/app_motion.dart';

class ModerationAppealsScreen extends StatefulWidget {
  const ModerationAppealsScreen({
    super.key,
    required this.repository,
    required this.onFeedback,
  });

  final AppealRepository repository;
  final ValueChanged<String> onFeedback;

  @override
  State<ModerationAppealsScreen> createState() =>
      _ModerationAppealsScreenState();
}

class _ModerationAppealsScreenState extends State<ModerationAppealsScreen> {
  late Future<ModerationAppealPage> future;
  String status = 'pending';

  @override
  void initState() {
    super.initState();
    future = _loadPage();
  }

  Future<ModerationAppealPage> _loadPage() =>
      widget.repository.listModerationAppeals(status: status);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text(
        '申诉案件复核',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
      ),
      backgroundColor: AppTheme.background,
      elevation: 0,
    ),
    body: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
          child: Row(
            children: [
              for (final filter in const [
                ('pending', '待复核'),
                ('reviewing', '审核中'),
                ('approved', '已通过'),
                ('rejected', '未通过'),
                ('', '全部'),
              ]) ...[
                _buildStatusChip(filter.$2, filter.$1),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<ModerationAppealPage>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, _) => Container(
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                  ),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 36, color: AppTheme.textSecondary),
                      const SizedBox(height: 10),
                      const Text('加载申诉案件失败', style: TextStyle(color: AppTheme.pink, fontSize: 13)),
                      const SizedBox(height: 12),
                      FilledButton.tonal(onPressed: _reload, child: const Text('重新加载')),
                    ],
                  ),
                );
              }
              final items = snapshot.data!.items;
              if (items.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 100),
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F1FA),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.rate_review_outlined, size: 28, color: Color(0xFF6B8299)),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              '暂无申诉案件',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF304A65),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '当前分类下没有需要复核的申诉记录',
                              style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _AppealCaseTile(
                    appeal: items[index],
                    onTap: () => _review(items[index]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _buildStatusChip(String label, String value) {
    final isSelected = status == value;
    return GestureDetector(
      onTap: () {
        if (status == value) return;
        setState(() {
          status = value;
          future = _loadPage();
        });
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6.5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.softBlue : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? const Color(0xFFD7E6FF) : const Color(0xFFD4DFE9),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? const Color(0xFF3E78CC) : const Color(0xFF6B8197),
          ),
        ),
      ),
    );
  }

  Future<void> _reload() async {
    final next = _loadPage();
    setState(() => future = next);
    await next;
  }

  Future<void> _review(ModerationAppeal summary) async {
    late final ModerationAppeal detail;
    try {
      detail = await widget.repository.getModerationAppeal(summary.id);
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '申诉详情加载失败'));
      }
      return;
    }
    if (!mounted) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
      builder: (_) => _ReviewSheet(appeal: detail, canReview: detail.isPending),
    );
    if (result == null) return;
    if (!mounted) return;
    final noteController = TextEditingController();
    String? validationError;
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(result == 'approved' ? '确认通过申诉' : '确认驳回申诉', style: const TextStyle(fontWeight: FontWeight.w800)),
          content: TextField(
            controller: noteController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: '复核说明（${result == 'rejected' ? '必填' : '选填'}）',
              hintText: result == 'rejected' ? '请说明驳回申诉的具体原因' : '可填写复核批注',
              errorText: validationError,
            ),
            onChanged: (_) {
              if (validationError != null) {
                setDialogState(() => validationError = null);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: result == 'rejected' ? AppTheme.pink : AppTheme.primary,
              ),
              onPressed: () {
                final text = noteController.text.trim();
                if (result == 'rejected' && text.isEmpty) {
                  setDialogState(() => validationError = '驳回申诉必须填写复核说明');
                  return;
                }
                Navigator.pop(dialogContext, text);
              },
              child: const Text('确认提交'),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
    if (note == null) return;
    try {
      await widget.repository.reviewAppeal(
        appealId: summary.id,
        result: result,
        note: note,
      );
      if (mounted) {
        widget.onFeedback(
          result == 'approved' ? '申诉已通过，内容已恢复' : '申诉已驳回，结果通知已生成',
        );
        await _reload();
      }
    } catch (error) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(error, fallback: '申诉复核失败'));
      }
    }
  }
}

class _AppealCaseTile extends StatelessWidget {
  const _AppealCaseTile({required this.appeal, required this.onTap});
  final ModerationAppeal appeal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor, statusBg) = switch (appeal.status) {
      'approved' => ('已通过', const Color(0xFF2C8C77), const Color(0xFFEDF8F5)),
      'rejected' => ('未通过', const Color(0xFFD44333), const Color(0xFFFFECEB)),
      'reviewing' => ('审核中', const Color(0xFF3E78CC), const Color(0xFFEDF5FC)),
      _ => ('待复核', const Color(0xFFBD772F), const Color(0xFFFFF4E8)),
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [AppTheme.cardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    appeal.status == 'approved'
                        ? Icons.check_circle_outline_rounded
                        : appeal.status == 'rejected'
                        ? Icons.cancel_outlined
                        : Icons.rate_review_outlined,
                    color: statusColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              appeal.targetTitle?.isNotEmpty == true ? appeal.targetTitle! : '内容申诉',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppTheme.textPrimary),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${appeal.targetType} · 理由：${appeal.reason}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF8FA3B8), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({required this.appeal, required this.canReview});
  final ModerationAppeal appeal;
  final bool canReview;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: 0.85,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          Text(
            appeal.targetTitle?.isNotEmpty == true
                ? appeal.targetTitle!
                : '内容申诉案件',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            '原处理方式：${_actionLabel(appeal.action ?? '')} · ${appeal.actionReason ?? '未注明原因'}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 16),
          const Text('原被处置内容', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4EDF5)),
            ),
            child: Text(
              appeal.targetContent ?? '原内容暂不可展示',
              style: const TextStyle(height: 1.5, fontSize: 13, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(height: 16),
          const Text('用户申诉理由', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appeal.reason, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                if (appeal.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    appeal.description,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.4,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (appeal.mediaIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '附件证据：${appeal.mediaIds.length} 张图片',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          if (canReview) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.pink,
                      side: const BorderSide(color: Color(0xFFFFD4D4)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context, 'rejected'),
                    child: const Text('驳回申诉'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context, 'approved'),
                    child: const Text('通过并恢复'),
                  ),
                ),
              ],
            ),
          ] else ...[
            Center(
              child: Text(
                '该申诉已${_statusLabel(appeal.status)}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

String _statusLabel(String status) => switch (status) {
  'pending' => '待复核',
  'reviewing' => '审核中',
  'approved' => '已通过',
  'rejected' => '已驳回',
  _ => status,
};

String _actionLabel(String action) => switch (action) {
  'delete' => '删除内容',
  'hide' => '隐藏内容',
  'mute' => '账号禁言',
  'ban' => '账号封禁',
  _ => action.isEmpty ? '内容处理' : action,
};
