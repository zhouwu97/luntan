import 'package:flutter/material.dart';

import '../data/api/appeal_repository.dart';
import '../data/api/api_client.dart';
import '../theme/app_theme.dart';

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
    appBar: AppBar(
      title: const Text('申诉案件'),
      actions: [
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: status,
            items: const [
              DropdownMenuItem(value: 'pending', child: Text('待复核')),
              DropdownMenuItem(value: 'reviewing', child: Text('审核中')),
              DropdownMenuItem(value: 'approved', child: Text('已通过')),
              DropdownMenuItem(value: 'rejected', child: Text('未通过')),
              DropdownMenuItem(value: '', child: Text('全部')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                status = value;
                future = _loadPage();
              });
            },
          ),
        ),
      ],
    ),
    body: FutureBuilder<ModerationAppealPage>(
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
        final items = snapshot.data!.items;
        if (items.isEmpty) {
          return const Center(
            child: Text(
              '暂无申诉案件',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
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
  );

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
      showDragHandle: true,
      builder: (_) => _ReviewSheet(appeal: detail, canReview: detail.isPending),
    );
    if (result == null) return;
    if (!mounted) return;
    final noteController = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(result == 'approved' ? '确认通过申诉' : '确认驳回申诉'),
        content: TextField(
          controller: noteController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '复核说明',
            hintText: '驳回时必须填写原因',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, noteController.text.trim()),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    noteController.dispose();
    if (note == null) return;
    if (result == 'rejected' && note.isEmpty) {
      widget.onFeedback('驳回申诉必须填写复核说明');
      return;
    }
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
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      onTap: onTap,
      title: Text(
        appeal.targetTitle?.isNotEmpty == true ? appeal.targetTitle! : '内容申诉',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${appeal.targetType} · ${_statusLabel(appeal.status)} · ${appeal.reason}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({required this.appeal, required this.canReview});
  final ModerationAppeal appeal;
  final bool canReview;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appeal.targetTitle?.isNotEmpty == true
                ? appeal.targetTitle!
                : '内容申诉',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '原处理：${_actionLabel(appeal.action ?? '')} · ${appeal.actionReason ?? ''}',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text('原内容', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            appeal.targetContent ?? '原内容暂不可展示',
            style: const TextStyle(height: 1.5),
          ),
          const SizedBox(height: 16),
          const Text('用户申诉', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(appeal.reason, style: const TextStyle(height: 1.5)),
          if (appeal.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              appeal.description,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ],
          if (appeal.mediaIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '证据图片：${appeal.mediaIds.length} 张',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
          if (canReview) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, 'rejected'),
                    child: const Text('驳回申诉'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, 'approved'),
                    child: const Text('通过并恢复'),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 16),
            Text(
              '该申诉已${_statusLabel(appeal.status)}',
              style: const TextStyle(color: AppTheme.textSecondary),
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
  'approved' => '通过',
  'rejected' => '驳回',
  _ => status,
};

String _actionLabel(String action) => switch (action) {
  'delete' => '删除内容',
  'hide' => '隐藏内容',
  'mute' => '账号禁言',
  'ban' => '账号封禁',
  _ => action.isEmpty ? '内容处理' : action,
};
