import 'package:flutter/material.dart';

import '../data/api/appeal_repository.dart';
import '../data/api/publish_repository.dart';
import '../theme/app_theme.dart';
import 'appeal_form_screen.dart';

class ModerationNoticeDetailScreen extends StatefulWidget {
  const ModerationNoticeDetailScreen({
    super.key,
    required this.repository,
    required this.actionId,
    this.publishRepository,
  });

  final AppealRepository repository;
  final String actionId;
  final PublishRepository? publishRepository;

  @override
  State<ModerationNoticeDetailScreen> createState() =>
      _ModerationNoticeDetailScreenState();
}

class _ModerationNoticeDetailScreenState
    extends State<ModerationNoticeDetailScreen> {
  late Future<ModerationAction> future;
  bool appealSubmitted = false;

  @override
  void initState() {
    super.initState();
    future = widget.repository.getModerationAction(widget.actionId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('处理详情')),
    body: FutureBuilder<ModerationAction>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: TextButton(
              onPressed: () => setState(
                () => future = widget.repository.getModerationAction(
                  widget.actionId,
                ),
              ),
              child: const Text('详情加载失败，重试'),
            ),
          );
        }
        return _content(snapshot.data!);
      },
    ),
  );

  Widget _content(ModerationAction action) {
    final targetLabel = action.targetType == 'comment'
        ? '评论'
        : action.targetType == 'user'
        ? '账号'
        : '帖子';
    final title = switch (action.action) {
      'delete' => '$targetLabel被删除',
      'hide' => '$targetLabel被隐藏',
      'mute' => '账号已被禁言',
      'ban' => '账号已被封禁',
      _ => '内容处理通知',
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
      children: [
        _NoticeHeader(title: title, time: action.createdAt),
        const SizedBox(height: 14),
        _InfoCard(
          children: [
            _InfoRow(
              label: '处理对象',
              value: action.targetTitle.isEmpty ? '内容' : action.targetTitle,
            ),
            _InfoRow(label: '处理类型', value: _actionLabel(action.action)),
            _InfoRow(label: '处理原因', value: action.reason),
            _InfoRow(label: '处理时间', value: _formatDate(action.createdAt)),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          '相关内容',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _ContentCard(action: action),
        const SizedBox(height: 18),
        if (action.appealable && !appealSubmitted)
          FilledButton.icon(
            onPressed: widget.publishRepository == null
                ? null
                : () async {
                    final submitted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => AppealFormScreen(
                          repository: widget.repository,
                          publishRepository: widget.publishRepository!,
                          action: action,
                        ),
                      ),
                    );
                    if (submitted == true && mounted) {
                      setState(() => appealSubmitted = true);
                    }
                  },
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('提交申诉'),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBlue,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            ),
            child: Text(
              appealSubmitted ? '申诉已提交，请等待复核结果' : '该通知不支持申诉',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _NoticeHeader extends StatelessWidget {
  const _NoticeHeader({required this.title, required this.time});
  final String title;
  final DateTime time;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: AppTheme.primaryGradient,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: Colors.white24,
          child: Icon(Icons.gavel_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _formatDate(time),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: children),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.action});
  final ModerationAction action;

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
          action.targetTitle.isEmpty ? '原内容' : action.targetTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          action.targetContent.isEmpty ? '原内容暂不可展示' : action.targetContent,
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        if (action.mediaIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '原处罚相关图片 · ${action.mediaIds.length} 张',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ],
    ),
  );
}

String _actionLabel(String action) => switch (action) {
  'delete' => '删除内容',
  'hide' => '隐藏内容',
  'restore' => '恢复内容',
  'mute' => '账号禁言',
  'ban' => '账号封禁',
  _ => action.isEmpty ? '内容处理' : action,
};

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
