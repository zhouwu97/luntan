import 'package:flutter/material.dart';

import '../data/api/appeal_repository.dart';
import '../theme/app_theme.dart';

class AppealDetailScreen extends StatefulWidget {
  const AppealDetailScreen({
    super.key,
    required this.repository,
    required this.appealId,
  });

  final AppealRepository repository;
  final String appealId;

  @override
  State<AppealDetailScreen> createState() => _AppealDetailScreenState();
}

class _AppealDetailScreenState extends State<AppealDetailScreen> {
  late Future<ModerationAppeal> future;

  @override
  void initState() {
    super.initState();
    future = widget.repository.getAppeal(widget.appealId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('申诉详情')),
    body: FutureBuilder<ModerationAppeal>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: TextButton(onPressed: _retry, child: const Text('加载失败，重试')),
          );
        }
        return _content(snapshot.data!);
      },
    ),
  );

  Widget _content(ModerationAppeal appeal) {
    final pending = appeal.isPending;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
      children: [
        _StatusHeader(appeal: appeal),
        const SizedBox(height: 14),
        _Block(
          title: '申诉对象',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appeal.targetTitle?.isNotEmpty == true
                    ? appeal.targetTitle!
                    : '内容处理',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              Text('处理类型：${_actionLabel(appeal.action ?? '')}'),
              if (appeal.actionReason?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text('处理原因：${appeal.actionReason}'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Block(
          title: '我的申诉理由',
          child: Text(appeal.reason, style: const TextStyle(height: 1.5)),
        ),
        if (appeal.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Block(
            title: '补充说明',
            child: Text(
              appeal.description,
              style: const TextStyle(height: 1.5),
            ),
          ),
        ],
        if (appeal.mediaIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Block(
            title: '补充证据',
            child: Text(
              '${appeal.mediaIds.length} 张图片已提交',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
        if (!pending && appeal.reviewerNote.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Block(
            title: '复核说明',
            child: Text(
              appeal.reviewerNote,
              style: const TextStyle(height: 1.5),
            ),
          ),
        ],
      ],
    );
  }

  void _retry() =>
      setState(() => future = widget.repository.getAppeal(widget.appealId));
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.appeal});
  final ModerationAppeal appeal;

  @override
  Widget build(BuildContext context) {
    final approved = appeal.status == 'approved';
    final rejected = appeal.status == 'rejected';
    final color = approved
        ? AppTheme.mint
        : rejected
        ? AppTheme.pink
        : AppTheme.primary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                approved
                    ? Icons.check_circle_rounded
                    : rejected
                    ? Icons.cancel_rounded
                    : Icons.hourglass_top_rounded,
                color: color,
              ),
              const SizedBox(width: 10),
              Text(
                _statusLabel(appeal.status),
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _DotStep(label: '已提交', active: true, color: color),
              Expanded(child: Divider(color: color.withValues(alpha: .35))),
              _DotStep(
                label: '审核中',
                active: appeal.isPending || approved || rejected,
                color: color,
              ),
              Expanded(child: Divider(color: color.withValues(alpha: .35))),
              _DotStep(
                label: '已处理',
                active: approved || rejected,
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '提交时间：${_formatDate(appeal.createdAt)}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          if (appeal.reviewedAt != null)
            Text(
              '处理时间：${_formatDate(appeal.reviewedAt!)}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

class _DotStep extends StatelessWidget {
  const _DotStep({
    required this.label,
    required this.active,
    required this.color,
  });
  final String label;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: active ? color : AppTheme.border,
        size: 18,
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(
          color: active ? color : AppTheme.textSecondary,
          fontSize: 11,
        ),
      ),
    ],
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      border: Border.all(color: AppTheme.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

String _statusLabel(String status) => switch (status) {
  'pending' => '已提交',
  'reviewing' => '审核中',
  'approved' => '申诉通过',
  'rejected' => '申诉未通过',
  'cancelled' => '已取消',
  _ => '申诉状态未知',
};

String _actionLabel(String action) => switch (action) {
  'delete' => '删除内容',
  'hide' => '隐藏内容',
  'mute' => '账号禁言',
  'ban' => '账号封禁',
  _ => action.isEmpty ? '内容处理' : action,
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
