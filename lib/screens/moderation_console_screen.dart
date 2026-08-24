import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../theme/app_theme.dart';

class ModerationConsoleScreen extends StatefulWidget {
  const ModerationConsoleScreen({
    super.key,
    required this.repository,
    required this.onFeedback,
  });

  final PlatformRepository repository;
  final ValueChanged<String> onFeedback;

  @override
  State<ModerationConsoleScreen> createState() =>
      _ModerationConsoleScreenState();
}

class _ModerationConsoleScreenState extends State<ModerationConsoleScreen> {
  final items = <ModerationCase>[];
  String status = '';
  String? nextCursor;
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  Object? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
      items.clear();
      nextCursor = null;
      hasMore = false;
    });
    try {
      final page = await widget.repository.listModerationCases(status: status);
      if (!mounted || request != generation) return;
      setState(() {
        items.addAll(page.items);
        nextCursor = page.nextCursor;
        hasMore = page.hasMore;
        loading = false;
      });
    } catch (cause) {
      if (mounted && request == generation) {
        setState(() {
          loading = false;
          error = cause;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final cursor = nextCursor;
    if (loading || loadingMore || !hasMore || cursor == null) return;
    final request = generation;
    setState(() => loadingMore = true);
    try {
      final page = await widget.repository.listModerationCases(
        status: status,
        cursor: cursor,
      );
      if (!mounted || request != generation) return;
      setState(() {
        final ids = items.map((item) => item.id).toSet();
        items.addAll(page.items.where((item) => ids.add(item.id)));
        nextCursor = page.nextCursor;
        hasMore = page.hasMore && page.nextCursor != cursor;
        loadingMore = false;
      });
    } catch (cause) {
      if (mounted && request == generation) {
        setState(() => loadingMore = false);
        widget.onFeedback(userFacingApiMessage(cause, fallback: '更多案件加载失败'));
      }
    }
  }

  Future<void> _action(ModerationCase item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final value in const ['hide', 'restore', 'delete'])
              ListTile(
                leading: Icon(
                  value == 'delete'
                      ? Icons.delete_outline
                      : Icons.visibility_outlined,
                ),
                title: Text(switch (value) {
                  'hide' => '隐藏内容',
                  'restore' => '恢复内容',
                  _ => '删除内容',
                }),
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (!mounted) return;
    if (action == 'delete') {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('确认删除内容？'),
              content: const Text('删除后内容将不再公开显示，此操作需要记录审核理由。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确认删除'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    final reason = await _askReason(action);
    if (reason == null) return;
    try {
      await widget.repository.applyModerationAction(
        caseId: item.id,
        action: action,
        reason: reason,
      );
      if (mounted) {
        widget.onFeedback('审核操作已提交');
        _load();
      }
    } catch (cause) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(cause, fallback: '审核操作失败'));
      }
    }
  }

  Future<String?> _askReason(String action) async {
    const reasons = ['广告', '人身攻击', '违规内容', '灌水', '复核通过', '其他'];
    var selected = action == 'restore' ? '复核通过' : '违规内容';
    final detailController = TextEditingController();
    String? validationError;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(action == 'restore' ? '填写恢复理由' : '填写审核理由'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: '理由分类'),
                items: reasons
                    .map(
                      (reason) =>
                          DropdownMenuItem(value: reason, child: Text(reason)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    selected = value;
                    validationError = null;
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: detailController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '补充说明（可选）',
                  errorText: validationError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final detail = detailController.text.trim();
                if (selected == '其他' && detail.isEmpty) {
                  setDialogState(() => validationError = '请选择理由或填写补充说明');
                  return;
                }
                Navigator.pop(
                  context,
                  detail.isEmpty ? selected : '$selected：$detail',
                );
              },
              child: const Text('提交'),
            ),
          ],
        ),
      ),
    );
    detailController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('审核中心'),
      actions: [
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: status,
            items: const [
              DropdownMenuItem(value: '', child: Text('全部')),
              DropdownMenuItem(value: 'pending', child: Text('待处理')),
              DropdownMenuItem(value: 'resolved', child: Text('已处理')),
            ],
            onChanged: (value) {
              if (value == null || value == status) return;
              setState(() => status = value);
              _load();
            },
          ),
        ),
      ],
    ),
    body: Builder(
      builder: (context) {
        if (loading && items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (error != null && items.isEmpty) {
          return Center(
            child: TextButton(onPressed: _load, child: const Text('加载失败，重试')),
          );
        }
        if (items.isEmpty) {
          return const Center(
            child: Text(
              '暂无可处理案件',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 240) _loadMore();
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + (loadingMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index >= items.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final item = items[index];
                return Card(
                  child: ListTile(
                    title: Text(
                      '${item.targetType} · ${item.targetId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.status} · 风险 ${item.riskLevel} · ${item.source}',
                    ),
                    trailing: item.status == 'resolved'
                        ? const Icon(Icons.check_circle_outline)
                        : const Icon(Icons.chevron_right),
                    onTap: item.status == 'resolved'
                        ? null
                        : () => _action(item),
                  ),
                );
              },
            ),
          ),
        );
      },
    ),
  );
}
