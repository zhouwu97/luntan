import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../theme/app_theme.dart';

class ModerationConsoleScreen extends StatefulWidget {
  const ModerationConsoleScreen({
    super.key,
    required this.repository,
    required this.onFeedback,
    this.onOpenAppeals,
  });

  final PlatformRepository repository;
  final ValueChanged<String> onFeedback;
  final VoidCallback? onOpenAppeals;

  @override
  State<ModerationConsoleScreen> createState() =>
      _ModerationConsoleScreenState();
}

class _MuteDuration {
  const _MuteDuration({required this.days, required this.permanent});

  final int days;
  final bool permanent;
}

class _ModerationConsoleScreenState extends State<ModerationConsoleScreen> {
  final items = <ModerationCase>[];
  String status = '';
  String? nextCursor;
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  Object? error;
  Object? loadMoreError;
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
      loadMoreError = null;
    });
    try {
      final page = await widget.repository.listModerationCases(status: status);
      if (!mounted || request != generation) return;
      setState(() {
        items.addAll(page.items);
        nextCursor = page.nextCursor;
        hasMore = page.hasMore;
        loading = false;
        loadMoreError = null;
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
        loadMoreError = null;
      });
    } catch (cause) {
      if (mounted && request == generation) {
        setState(() {
          loadingMore = false;
          loadMoreError = cause;
        });
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
            for (final value
                in item.targetType == 'user'
                    ? const ['mute', 'ban', 'restore']
                    : const ['hide', 'restore', 'delete'])
              ListTile(
                leading: Icon(
                  value == 'delete'
                      ? Icons.delete_outline
                      : value == 'ban'
                      ? Icons.block_outlined
                      : value == 'mute'
                      ? Icons.volume_off_outlined
                      : Icons.visibility_outlined,
                ),
                title: Text(switch (value) {
                  'hide' => '隐藏内容',
                  'restore' => '恢复内容',
                  'mute' => '禁言账号',
                  'ban' => '封禁账号',
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
    var durationDays = 0;
    var permanent = false;
    if (action == 'mute') {
      final duration = await _askMuteDuration();
      if (duration == null) return;
      durationDays = duration.days;
      permanent = duration.permanent;
    }
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
        durationDays: durationDays,
        permanent: permanent,
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

  Future<_MuteDuration?> _askMuteDuration() async {
    var selected = 7;
    final customController = TextEditingController();
    final result = await showDialog<_MuteDuration>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择禁言时间'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: '禁言时间'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 天')),
                  DropdownMenuItem(value: 7, child: Text('7 天')),
                  DropdownMenuItem(value: 30, child: Text('30 天')),
                  DropdownMenuItem(value: -1, child: Text('自定义')),
                  DropdownMenuItem(value: 0, child: Text('永久')),
                ],
                onChanged: (value) =>
                    setDialogState(() => selected = value ?? 7),
              ),
              if (selected == -1)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextField(
                    controller: customController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '自定义天数（1-365）',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                selected == 0
                    ? '将永久禁止该用户发表评论，不影响其浏览权限。'
                    : '将禁止该用户发表评论 ${selected == -1 ? '（自定义）' : '$selected 天'}，不影响其浏览权限。',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            if (selected != 0)
              FilledButton(
                onPressed: () {
                  final days = selected == -1
                      ? int.tryParse(customController.text.trim())
                      : selected;
                  if (days == null || days < 1 || days > 365) return;
                  Navigator.pop(
                    dialogContext,
                    _MuteDuration(days: days, permanent: false),
                  );
                },
                child: const Text('确认期限'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  const _MuteDuration(days: 0, permanent: true),
                ),
                child: const Text('确认永久禁言'),
              ),
          ],
        ),
      ),
    );
    customController.dispose();
    return result;
  }

  Future<void> _openCase(ModerationCase item) async {
    try {
      final detail = await widget.repository.getModerationCase(item.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: .82,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text(
                  '举报案件 #${detail.id}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '状态：${detail.status} · 风险：${detail.riskLevel} · 来源：${detail.source}',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 18),
                const Text(
                  '被举报内容',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '${_detailText(detail.target, 'title')}\n\n${_detailText(detail.target, 'content')}',
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ),
                Text(
                  '作者：${_detailText(detail.target, 'author_name')}',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 14),
                const Text(
                  '举报信息',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                Text(
                  '举报人数：${_detailText(detail.report, 'count')}\n原因：${_detailText(detail.report, 'reasons')}',
                ),
                const SizedBox(height: 14),
                if (detail.account.isNotEmpty) ...[
                  const Text(
                    '账号情况',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  Text(
                    '账号状态：${_detailText(detail.account, 'status')}\n历史处罚：${_detailText(detail.account, 'punishment_count')}\n近期举报数：${_detailText(detail.account, 'report_count')}',
                  ),
                  const SizedBox(height: 14),
                ],
                if (detail.status != 'resolved')
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _action(item);
                    },
                    icon: const Icon(Icons.gavel_outlined),
                    label: const Text('处理案件'),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (cause) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(cause, fallback: '案件详情加载失败'));
      }
    }
  }

  String _detailText(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null || '$value'.trim().isEmpty) return '—';
    return '$value';
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
        if (widget.onOpenAppeals != null)
          TextButton.icon(
            onPressed: widget.onOpenAppeals,
            icon: const Icon(Icons.rate_review_outlined, size: 18),
            label: const Text('申诉'),
          ),
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
              itemCount:
                  items.length + (loadingMore || loadMoreError != null ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index >= items.length) {
                  return loadingMore
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: TextButton(
                            onPressed: _loadMore,
                            child: const Text('加载失败 · 点击重试'),
                          ),
                        );
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
                    onTap: () => _openCase(item),
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
