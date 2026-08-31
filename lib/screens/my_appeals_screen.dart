import 'package:flutter/material.dart';

import '../data/api/appeal_repository.dart';
import '../theme/app_theme.dart';
import 'appeal_detail_screen.dart';

class MyAppealsScreen extends StatefulWidget {
  const MyAppealsScreen({super.key, required this.repository});

  final AppealRepository repository;

  @override
  State<MyAppealsScreen> createState() => _MyAppealsScreenState();
}

class _MyAppealsScreenState extends State<MyAppealsScreen> {
  late Future<AppealPage> future;

  @override
  void initState() {
    super.initState();
    future = widget.repository.listAppeals();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text(
        '我的申诉',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
      ),
      backgroundColor: AppTheme.background,
      elevation: 0,
    ),
    body: FutureBuilder<AppealPage>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, _) => Container(
              height: 80,
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
                const Text('加载申诉记录失败', style: TextStyle(color: AppTheme.pink, fontSize: 13)),
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: _reload, child: const Text('重新加载')),
              ],
            ),
          );
        }
        final appeals = snapshot.data!.items;
        if (appeals.isEmpty) {
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
                        '还没有申诉记录',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF304A65),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '当你的内容或账号受到处置时，可在此发起申诉复核',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        final pending = appeals.where((item) => item.isPending).length;
        final completed = appeals.length - pending;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
            children: [
              _SummaryCard(pending: pending, completed: completed),
              const SizedBox(height: 14),
              ...appeals.map(
                (appeal) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AppealTile(
                    appeal: appeal,
                    onTap: () => _open(appeal),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _reload() async {
    final next = widget.repository.listAppeals();
    setState(() => future = next);
    await next;
  }

  Future<void> _open(ModerationAppeal appeal) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppealDetailScreen(
          repository: widget.repository,
          appealId: appeal.id,
        ),
      ),
    );
    if (mounted) _reload();
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.pending, required this.completed});
  final int pending;
  final int completed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border),
      boxShadow: const [AppTheme.cardShadow],
    ),
    child: Row(
      children: [
        _Stat(value: pending, label: '复核中', color: const Color(0xFFBD772F)),
        Container(width: 1, height: 28, color: const Color(0xFFE2ECF6)),
        _Stat(value: completed, label: '已完成', color: const Color(0xFF2C8C77)),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _AppealTile extends StatelessWidget {
  const _AppealTile({required this.appeal, required this.onTap});
  final ModerationAppeal appeal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor, statusBg) = switch (appeal.status) {
      'approved' => ('已通过', const Color(0xFF2C8C77), const Color(0xFFEDF8F5)),
      'rejected' => ('未通过', const Color(0xFFD44333), const Color(0xFFFFECEB)),
      'reviewing' => ('审核中', const Color(0xFF3E78CC), const Color(0xFFEDF5FC)),
      _ => ('已提交', const Color(0xFFBD772F), const Color(0xFFFFF4E8)),
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
                        : Icons.hourglass_top_rounded,
                    color: statusColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appeal.targetTitle?.isNotEmpty == true
                            ? appeal.targetTitle!
                            : _actionLabel(appeal.action ?? ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatDate(appeal.createdAt)} · 申诉理由：${appeal.reason}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
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

String _actionLabel(String action) => switch (action) {
  'delete' => '帖子删除申诉',
  'hide' => '内容隐藏申诉',
  'mute' => '禁言申诉',
  'ban' => '封禁申诉',
  _ => '处理申诉',
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
