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
    appBar: AppBar(title: const Text('我的申诉')),
    body: FutureBuilder<AppealPage>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: TextButton(onPressed: _reload, child: const Text('加载失败，重试')),
          );
        }
        final appeals = snapshot.data!.items;
        if (appeals.isEmpty) {
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              children: const [
                SizedBox(height: 220),
                Center(
                  child: Text(
                    '还没有申诉记录',
                    style: TextStyle(color: AppTheme.textSecondary),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
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
      gradient: AppTheme.primaryGradient,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
    ),
    child: Row(
      children: [
        _Stat(value: pending, label: '审核中'),
        _Stat(value: completed, label: '已完成'),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
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
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: CircleAvatar(
        backgroundColor: AppTheme.surfaceBlue,
        child: Icon(
          appeal.status == 'approved'
              ? Icons.check
              : appeal.status == 'rejected'
              ? Icons.close
              : Icons.hourglass_top,
          color: AppTheme.primary,
        ),
      ),
      title: Text(
        appeal.targetTitle?.isNotEmpty == true
            ? appeal.targetTitle!
            : _actionLabel(appeal.action ?? ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${_statusLabel(appeal.status)} · ${_formatDate(appeal.createdAt)}',
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

String _statusLabel(String status) => switch (status) {
  'pending' => '已提交',
  'reviewing' => '审核中',
  'approved' => '已通过',
  'rejected' => '未通过',
  _ => '已取消',
};

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
