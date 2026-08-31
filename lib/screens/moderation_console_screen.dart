import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../theme/app_theme.dart';
import '../theme/app_motion.dart';

class ModerationConsoleScreen extends StatefulWidget {
  const ModerationConsoleScreen({
    super.key,
    required this.repository,
    required this.onFeedback,
    this.onOpenAppeals,
    this.onOpenRecommendations,
  });

  final PlatformRepository repository;
  final ValueChanged<String> onFeedback;
  final VoidCallback? onOpenAppeals;
  final VoidCallback? onOpenRecommendations;

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
  String status = 'pending';
  String? sourceFilter;
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

  List<ModerationCase> get _filteredItems {
    if (sourceFilter == null || sourceFilter!.isEmpty) return items;
    return items.where((item) => item.source == sourceFilter).toList();
  }

  Future<void> _action(ModerationCase item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  '选择处置动作',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
              ),
              const SizedBox(height: 4),
              for (final value
                  in item.targetType == 'user'
                      ? const ['mute', 'ban', 'restore']
                      : const ['hide', 'restore', 'delete'])
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFD),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE4EDF5)),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: value == 'delete' || value == 'ban'
                            ? AppTheme.softRose
                            : (value == 'mute' ? AppTheme.softAmber : AppTheme.softBlue),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        value == 'delete'
                            ? Icons.delete_outline_rounded
                            : value == 'ban'
                            ? Icons.block_rounded
                            : value == 'mute'
                            ? Icons.volume_off_rounded
                            : Icons.visibility_outlined,
                        color: value == 'delete' || value == 'ban'
                            ? AppTheme.pink
                            : (value == 'mute' ? AppTheme.orange : AppTheme.primary),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      switch (value) {
                        'hide' => '隐藏内容（前台不可见）',
                        'restore' => '恢复内容（解除限制）',
                        'mute' => '禁言账号（禁止发帖评论）',
                        'ban' => '封禁账号（限制全站登录）',
                        _ => '删除违规内容（永久清理）',
                      },
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF8FA3B8), size: 18),
                    onTap: () => Navigator.pop(context, value),
                  ),
                ),
            ],
          ),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('确认删除内容？', style: TextStyle(fontWeight: FontWeight.w800)),
              content: const Text('删除后内容将不再公开显示，此操作需要记录审核理由。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.pink),
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
        widget.onFeedback('审核处置已生效');
        _load();
      }
    } catch (cause) {
      if (mounted) {
        final msg = userFacingApiMessage(cause, fallback: '审核操作失败');
        if (msg.contains('conflict') || msg.contains('409') || msg.contains('已处理')) {
          widget.onFeedback('该案件已由其他管理员处理，列表已自动刷新');
          _load();
        } else {
          widget.onFeedback(msg);
        }
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('选择禁言时间', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: '禁言期限'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 天')),
                  DropdownMenuItem(value: 7, child: Text('7 天')),
                  DropdownMenuItem(value: 30, child: Text('30 天')),
                  DropdownMenuItem(value: -1, child: Text('自定义天数')),
                  DropdownMenuItem(value: 0, child: Text('永久禁言')),
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
                    ? '将永久禁止该用户发表评论与发帖，不影响其浏览权限。'
                    : '将禁止该用户发表评论与发帖 ${selected == -1 ? '（自定义）' : '$selected 天'}。',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
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
                style: FilledButton.styleFrom(backgroundColor: AppTheme.pink),
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: .85,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _humanTitle(item),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    _statusBadge(detail.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '案件编号：${detail.id} · ${_formatSource(detail.source)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 16),
                const Text(
                  '被举报内容',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F9FD),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2ECF6)),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_detailText(detail.target, 'title') != '—') ...[
                        Text(
                          _detailText(detail.target, 'title'),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        _detailText(detail.target, 'content'),
                        style: const TextStyle(height: 1.5, fontSize: 13, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '作者：${_detailText(detail.target, 'author_name')} · 社区：${detail.communityId.isEmpty ? '平台全域' : detail.communityId}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  '举报信息',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '举报人数：${_detailText(detail.report, 'count')} 次\n举报理由：${_detailText(detail.report, 'reasons')}',
                    style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.textSecondary),
                  ),
                ),
                if (detail.account.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '账号情况',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '账号状态：${_detailText(detail.account, 'status')}\n历史处罚：${_detailText(detail.account, 'punishment_count')} 次\n近期被举报：${_detailText(detail.account, 'report_count')} 次',
                      style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.textSecondary),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (detail.status != 'resolved')
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _action(item);
                    },
                    icon: const Icon(Icons.gavel_rounded, size: 18),
                    label: const Text('执行处置动作'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
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
    const reasons = ['广告营销', '人身攻击与辱骂', '违规违法内容', '灌水刷屏', '复核通过无违规', '其他理由'];
    var selected = action == 'restore' ? '复核通过无违规' : '违规违法内容';
    final detailController = TextEditingController();
    String? validationError;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(action == 'restore' ? '填写恢复理由' : '填写审核处置理由', style: const TextStyle(fontWeight: FontWeight.w800)),
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
                  labelText: '补充说明（必填或选填）',
                  hintText: '输入具体处置说明',
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
                if (selected == '其他理由' && detail.isEmpty) {
                  setDialogState(() => validationError = '请填写具体的补充说明');
                  return;
                }
                Navigator.pop(
                  context,
                  detail.isEmpty ? selected : '$selected：$detail',
                );
              },
              child: const Text('确认提交'),
            ),
          ],
        ),
      ),
    );
    detailController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final displayItems = _filteredItems;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          '审核与处罚',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          if (widget.onOpenRecommendations != null)
            IconButton(
              onPressed: widget.onOpenRecommendations,
              icon: const Icon(Icons.push_pin_outlined),
              tooltip: '首页推荐',
            ),
          if (widget.onOpenAppeals != null)
            TextButton.icon(
              onPressed: widget.onOpenAppeals,
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: const Text('申诉'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips 筛选栏
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
            child: Row(
              children: [
                _buildStatusChip('待处理', 'pending'),
                const SizedBox(width: 8),
                _buildStatusChip('全部案件', ''),
                const SizedBox(width: 8),
                _buildStatusChip('已处理', 'resolved'),
                const SizedBox(width: 14),
                Container(width: 1, height: 20, color: const Color(0xFFD5E2EE)),
                const SizedBox(width: 14),
                _buildSourceChip('全部来源', null),
                const SizedBox(width: 8),
                _buildSourceChip('用户举报', 'report'),
                const SizedBox(width: 8),
                _buildSourceChip('自动规则', 'auto'),
              ],
            ),
          ),

          Expanded(
            child: _buildBody(displayItems),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, String value) {
    final isSelected = status == value;
    return GestureDetector(
      onTap: () {
        if (status == value) return;
        setState(() => status = value);
        _load();
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

  Widget _buildSourceChip(String label, String? value) {
    final isSelected = sourceFilter == value;
    return GestureDetector(
      onTap: () => setState(() => sourceFilter = value),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEDF8F5) : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? const Color(0xFFD0EFE6) : const Color(0xFFD4DFE9),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? const Color(0xFF2C8C77) : const Color(0xFF6B8197),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<ModerationCase> displayItems) {
    if (loading && items.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => Container(
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 14, width: 140, color: const Color(0xFFEAF0F6)),
              const SizedBox(height: 10),
              Container(height: 12, width: 220, color: const Color(0xFFEAF0F6)),
              const Spacer(),
              Row(
                children: [
                  Container(height: 18, width: 60, color: const Color(0xFFEAF0F6)),
                  const SizedBox(width: 8),
                  Container(height: 18, width: 60, color: const Color(0xFFEAF0F6)),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (error != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 36, color: AppTheme.textSecondary),
            const SizedBox(height: 10),
            const Text('加载案件失败', style: TextStyle(color: AppTheme.pink, fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _load,
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    if (displayItems.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
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
                    child: const Icon(Icons.verified_user_outlined, size: 28, color: Color(0xFF6B8299)),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '暂无可处理案件',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF304A65),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '当前分类下没有待处理或符合筛选的案件',
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
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 240) _loadMore();
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
          itemCount: displayItems.length + (loadingMore || loadMoreError != null ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index >= displayItems.length) {
              return loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                    )
                  : Center(
                      child: TextButton(
                        onPressed: _loadMore,
                        child: const Text('加载失败 · 点击重试'),
                      ),
                    );
            }
            final item = displayItems[index];
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
                  onTap: () => _openCase(item),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 层级 1: 业务语义标题 + 处置状态
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _humanTitle(item),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            _statusBadge(item.status),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // 层级 2: 人类可读原因与摘要
                        Text(
                          _humanDescription(item),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 层级 3: 降级 Monospace 标识与语义 Badges
                        Row(
                          children: [
                            Text(
                              '#${item.targetId}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                                color: Color(0xFF8B9FB3),
                              ),
                            ),
                            const Spacer(),
                            _riskBadge(item.riskLevel),
                            const SizedBox(width: 6),
                            _sourceBadge(item.source),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _humanTitle(ModerationCase item) {
    return switch (item.targetType) {
      'post' => '帖子内容审核',
      'comment' => '评论内容审核',
      'user' => '用户账号处置',
      _ => '内容审核案件',
    };
  }

  String _humanDescription(ModerationCase item) {
    final prefix = switch (item.source) {
      'report' || 'user_report' => '用户举报触发 · 需复核内容是否违规',
      'auto' || 'auto_rule' => '系统敏感词或自动规则拦截 · 待人工研判',
      _ => '治理巡检案件',
    };
    if (item.communityId.isNotEmpty) {
      return '$prefix（社区：${item.communityId}）';
    }
    return prefix;
  }

  String _formatSource(String source) => switch (source) {
    'report' || 'user_report' => '用户举报',
    'auto' || 'auto_rule' => '自动规则',
    _ => '系统巡检',
  };

  Widget _statusBadge(String status) {
    final isResolved = status == 'resolved';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: isResolved ? const Color(0xFFEDF8F5) : const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isResolved ? '已处理' : '待处理',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isResolved ? const Color(0xFF2C8C77) : const Color(0xFFBD772F),
        ),
      ),
    );
  }

  Widget _riskBadge(String riskLevel) {
    final (label, color, bg) = switch (riskLevel) {
      'high' => ('高风险', const Color(0xFFD44333), const Color(0xFFFFECEB)),
      'medium' => ('中风险', const Color(0xFFBD772F), const Color(0xFFFFF4E8)),
      _ => ('常规', const Color(0xFF3E78CC), const Color(0xFFEDF5FC)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _sourceBadge(String source) {
    final label = _formatSource(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF637B92)),
      ),
    );
  }
}
