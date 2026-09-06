import 'store_order_aftercare_screen.dart';
import 'package:flutter/material.dart';

import '../data/api/platform_repository.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';

typedef StoreOrderUserActivityCallback = void Function(String userId, int tab);

/// 兑换审核列表。管理员审核的是一次兑换申请，而不是给单条帖子打标签。
class StoreOrderReviewScreen extends StatefulWidget {
  const StoreOrderReviewScreen({
    super.key,
    required this.repository,
    this.onOpenUserActivity,
    this.onFeedback,
  });

  final PlatformRepository repository;
  final StoreOrderUserActivityCallback? onOpenUserActivity;
  final ValueChanged<String>? onFeedback;

  @override
  State<StoreOrderReviewScreen> createState() => _StoreOrderReviewScreenState();
}

class _StoreOrderReviewScreenState extends State<StoreOrderReviewScreen> {
  final List<AdminStoreOrder> _items = <AdminStoreOrder>[];
  String? _nextCursor;
  String? _error;
  String? _loadMoreError;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String _selectedGroup = 'todo';
  Set<String> _selectedStatuses = const <String>{};
  int _requestGeneration = 0;
  Map<String, int> _counts = const <String, int>{};
  bool _combinedStatusSupported = true;

  static const _statusFilters = <({String value, String label, String group})>[
    (value: 'pending_review', label: '待审核', group: 'todo'),
    (value: 'ready_to_ship', label: '待发货', group: 'todo'),
    (value: 'return_requested', label: '退货待审核', group: 'todo'),
    (value: 'refund_pending', label: '待退款', group: 'todo'),
    (value: 'awaiting_address', label: '待填地址', group: 'processing'),
    (value: 'shipped', label: '已发货', group: 'processing'),
    (value: 'refunded', label: '已退款', group: 'done'),
    (value: 'cancelled', label: '已取消', group: 'done'),
    (value: 'completed', label: '已完成', group: 'done'),
    (value: 'rejected', label: '已拒绝', group: 'done'),
  ];

  static const _groups = <({String value, String label})>[
    (value: 'all', label: '全部'),
    (value: 'todo', label: '待我操作'),
    (value: 'processing', label: '处理中'),
    (value: 'done', label: '已结束'),
  ];

  List<String> get _effectiveStatuses {
    if (_selectedStatuses.isNotEmpty) return _selectedStatuses.toList()..sort();
    if (_selectedGroup == 'all') return const <String>[];
    return _statusFilters
        .where((filter) => filter.group == _selectedGroup)
        .map((filter) => filter.value)
        .toList();
  }

  String get _requestStatus {
    final statuses = _effectiveStatuses;
    if (statuses.isEmpty ||
        (!_combinedStatusSupported && statuses.length > 1)) {
      return 'all';
    }
    return statuses.join(',');
  }

  String get _selectionKey {
    final selected = _selectedStatuses.toList()..sort();
    return '$_selectedGroup:${selected.join(',')}';
  }

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_requestGeneration;
    final selectionKey = _selectionKey;
    var requestStatus = _requestStatus;

    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _loadMoreError = null;
      _items.clear();
      _nextCursor = null;
      _hasMore = false;
    });
    try {
      final countsFuture = widget.repository.getStoreOrderCounts().catchError(
        (_) => const <String, int>{},
      );
      AdminStoreOrderPage page;
      try {
        page = await widget.repository.listStoreOrderPage(
          status: requestStatus,
        );
      } catch (_) {
        if (!requestStatus.contains(',')) rethrow;
        // 兼容尚未支持联合状态查询的旧服务端，升级期间页面仍可正常使用。
        _combinedStatusSupported = false;
        requestStatus = 'all';
        page = await widget.repository.listStoreOrderPage(
          status: requestStatus,
        );
      }
      final counts = await countsFuture;
      if (!mounted ||
          generation != _requestGeneration ||
          selectionKey != _selectionKey) {
        return;
      }
      setState(() {
        _items.addAll(_filterItemsIfNeeded(page.items, requestStatus));
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _counts = counts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          generation != _requestGeneration ||
          selectionKey != _selectionKey) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    final generation = _requestGeneration;
    final requestStatus = _requestStatus;
    final selectionKey = _selectionKey;

    if (_loadingMore || !_hasMore || cursor == null || cursor.isEmpty) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await widget.repository.listStoreOrderPage(
        status: requestStatus,
        cursor: cursor,
      );
      if (!mounted ||
          generation != _requestGeneration ||
          selectionKey != _selectionKey ||
          cursor != _nextCursor) {
        return;
      }
      setState(() {
        _items.addAll(_filterItemsIfNeeded(page.items, requestStatus));
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted ||
          generation != _requestGeneration ||
          selectionKey != _selectionKey) {
        return;
      }
      setState(() {
        _loadingMore = false;
        _loadMoreError = '$error';
      });
    }
  }

  Iterable<AdminStoreOrder> _filterItemsIfNeeded(
    List<AdminStoreOrder> items,
    String requestStatus,
  ) {
    final statuses = _effectiveStatuses.toSet();
    if (requestStatus != 'all' || statuses.isEmpty) return items;
    return items.where((item) => statuses.contains(_statusValue(item)));
  }

  String _statusValue(AdminStoreOrder item) {
    if (item.status == 'pending_review' ||
        item.status == 'rejected' ||
        item.status == 'cancelled') {
      return item.status;
    }
    return item.fulfillmentStatus;
  }

  Future<void> _refresh() => _loadFirstPage();

  Future<void> _selectGroup(String group) async {
    if (group == _selectedGroup && _selectedStatuses.isEmpty) return;
    setState(() {
      _selectedGroup = group;
      _selectedStatuses = const <String>{};
    });
    await _loadFirstPage();
  }

  Future<void> _openDetail(AdminStoreOrder item) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => StoreOrderReviewDetailScreen(
          repository: widget.repository,
          orderId: item.id,
          onOpenUserActivity: widget.onOpenUserActivity,
          onFeedback: widget.onFeedback,
        ),
      ),
    );
    if (mounted) {
      await _loadFirstPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          '兑换订单',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_todoCount > 0) _buildActionNotice(),
          _buildStatusFilters(),
          Expanded(
            child: RefreshIndicator(onRefresh: _refresh, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  int get _todoCount => _statusFilters
      .where((filter) => filter.group == 'todo')
      .fold(0, (total, filter) => total + (_counts[filter.value] ?? 0));

  int _groupCount(String group) {
    if (group == 'all') return _counts['all'] ?? 0;
    return _statusFilters
        .where((filter) => filter.group == group)
        .fold(0, (total, filter) => total + (_counts[filter.value] ?? 0));
  }

  Widget _buildActionNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [AppTheme.cardShadow],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '有 $_todoCount 笔订单需要你处理',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '及时完成审核、发货或售后处理',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _selectGroup('todo'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.orange,
              backgroundColor: AppTheme.softAmber,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            child: const Text(
              '去处理',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilters() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 46,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F0F7),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    for (final group in _groups)
                      Expanded(
                        child: _buildGroupButton(group.value, group.label),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: _selectedStatuses.isNotEmpty,
              label: Text('${_selectedStatuses.length}'),
              child: IconButton(
                tooltip: '筛选订单状态',
                onPressed: _showFilterSheet,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.border),
                  minimumSize: const Size(44, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.filter_list_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupButton(String value, String label) {
    final selected = value == _selectedGroup;
    final count = _groupCount(value);
    return InkWell(
      key: ValueKey('order-group-$value'),
      onTap: () => _selectGroup(value),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected ? const [AppTheme.cardShadow] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            if (count > 0 && value != 'all') ...[
              const SizedBox(width: 3),
              Text(
                '$count',
                style: TextStyle(
                  color: value == 'todo' ? AppTheme.orange : AppTheme.primary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showFilterSheet() async {
    var draft = Set<String>.of(_selectedStatuses);
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              18 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '筛选订单状态',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setSheetState(() => draft.clear()),
                      child: const Text('清除筛选'),
                    ),
                  ],
                ),
                for (final group in _groups.where(
                  (group) => group.value != 'all',
                )) ...[
                  const SizedBox(height: 12),
                  Text(
                    group.label,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final filter in _statusFilters.where(
                        (filter) => filter.group == group.value,
                      ))
                        FilterChip(
                          label: Text(
                            '${filter.label} · ${_counts[filter.value] ?? 0}',
                          ),
                          selected: draft.contains(filter.value),
                          showCheckmark: false,
                          onSelected: (value) => setSheetState(() {
                            value
                                ? draft.add(filter.value)
                                : draft.remove(filter.value);
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, draft),
                        child: const Text('应用筛选'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedStatuses = selected);
    await _loadFirstPage();
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 220),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const SizedBox(height: 120),
          const Center(child: Text('兑换申请加载失败')),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: _loadFirstPage,
              child: const Text('重新加载'),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        children: [
          const SizedBox(height: 150),
          Center(
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppTheme.softBlue,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppTheme.primary,
                size: 27,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              '当前没有相关订单',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              '新的兑换申请或履约状态会显示在这里',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
        ],
      );
    }
    final footerCount = _hasMore ? 1 : 0;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
      itemCount: _items.length + footerCount,
      separatorBuilder: (_, index) => index < _items.length - 1
          ? const SizedBox(height: 10)
          : const SizedBox(height: 6),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return OutlinedButton(
            onPressed: _loadMore,
            child: Text(_loadMoreError == null ? '加载更多申请' : '加载失败，点击重试'),
          );
        }
        return _StoreOrderListTile(
          item: _items[index],
          onTap: () => _openDetail(_items[index]),
        );
      },
    );
  }
}

class _StoreOrderListTile extends StatelessWidget {
  const _StoreOrderListTile({required this.item, required this.onTap});

  final AdminStoreOrder item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = item.nickname.trim().isEmpty ? item.username : item.nickname;
    final status = _statusAppearance(item);
    final shipping = item.shipping;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: status.background,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      status.icon,
                      color: status.foreground,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(
                              Icons.account_circle_outlined,
                              size: 14,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              relativeTimeLabel(item.createdAt),
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: status.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        color: status.foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _metric(
                    Icons.workspace_premium_outlined,
                    '${item.points} 积分',
                  ),
                  const SizedBox(width: 16),
                  _metric(
                    Icons.account_balance_wallet_outlined,
                    '当前 ${item.userPoints}',
                  ),
                ],
              ),
              if (shipping != null) ...[
                const SizedBox(height: 13),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F9FC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.fulfillmentStatus == 'shipped'
                            ? Icons.local_shipping_outlined
                            : Icons.location_on_outlined,
                        color: AppTheme.primary,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _shippingSummary(shipping, item.fulfillmentStatus),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (item.invalidatedPoints > 0 ||
                  item.reviewReason.trim().isNotEmpty ||
                  (item.status != 'pending_review' &&
                      item.reviewedAt != null)) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                if (item.invalidatedPoints > 0)
                  _note(
                    Icons.remove_circle_outline,
                    '已剔除 ${item.invalidatedCount} 笔奖励，共 ${item.invalidatedPoints} 积分',
                    AppTheme.orange,
                  ),
                if (item.reviewReason.trim().isNotEmpty)
                  _note(
                    Icons.notes_rounded,
                    item.reviewReason,
                    AppTheme.textSecondary,
                  ),
                if (item.status != 'pending_review' && item.reviewedAt != null)
                  _note(
                    Icons.verified_user_outlined,
                    '审核于 ${relativeTimeLabel(item.reviewedAt!)}',
                    AppTheme.textSecondary,
                  ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _timelineLabel(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: Text(_actionLabel(item)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: AppTheme.textSecondary),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _note(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 11.5, height: 1.35),
          ),
        ),
      ],
    ),
  );

  String _actionLabel(AdminStoreOrder order) {
    if (order.status == 'pending_review') return '审核订单';
    return switch (order.fulfillmentStatus) {
      'ready_to_ship' => '填写物流',
      'return_requested' => '审核退货',
      'refund_pending' => '处理退款',
      'awaiting_address' => '查看进度',
      _ => '查看详情',
    };
  }

  String _timelineLabel(AdminStoreOrder order) {
    if (order.status == 'pending_review') {
      return '提交申请 · ${relativeTimeLabel(order.createdAt)}';
    }
    if (order.reviewedAt != null) {
      return '审核完成 · ${relativeTimeLabel(order.reviewedAt!)}';
    }
    return '状态更新 · ${relativeTimeLabel(order.createdAt)}';
  }

  ({String label, IconData icon, Color foreground, Color background})
  _statusAppearance(AdminStoreOrder item) {
    final label = _statusLabel(item);
    if (item.status == 'rejected' || item.fulfillmentStatus == 'cancelled') {
      return (
        label: label,
        icon: Icons.close_rounded,
        foreground: AppTheme.orange,
        background: const Color(0xFFFFF3EA),
      );
    }
    switch (item.fulfillmentStatus) {
      case 'awaiting_address':
        return (
          label: '待填地址',
          icon: Icons.edit_location_alt_outlined,
          foreground: AppTheme.orange,
          background: const Color(0xFFFFF3EA),
        );
      case 'ready_to_ship':
        return (
          label: '待发货',
          icon: Icons.inventory_2_outlined,
          foreground: AppTheme.primary,
          background: AppTheme.softBlue,
        );
      case 'shipped':
        return (
          label: '已发货',
          icon: Icons.local_shipping_outlined,
          foreground: AppTheme.primary,
          background: AppTheme.softBlue,
        );
      case 'completed':
        return (
          label: '已完成',
          icon: Icons.check_circle_outline_rounded,
          foreground: AppTheme.mint,
          background: AppTheme.softMint,
        );
      case 'return_requested':
      case 'refund_pending':
      case 'refunded':
        return (
          label: label,
          icon: Icons.assignment_return_outlined,
          foreground: AppTheme.orange,
          background: const Color(0xFFFFF3EA),
        );
      default:
        return (
          label: label,
          icon: Icons.card_giftcard_outlined,
          foreground: AppTheme.pink,
          background: AppTheme.softRose,
        );
    }
  }

  String _statusLabel(AdminStoreOrder item) {
    if (item.status == 'approved') {
      return switch (item.fulfillmentStatus) {
        'awaiting_address' => '审核通过 · 待填地址',
        'ready_to_ship' => '待发货',
        'return_requested' => '退货待审核',
        'refund_pending' => '待退款',
        'refunded' => '已退款',
        'shipped' => '已发货',
        'completed' => '已完成',
        'cancelled' => '已取消',
        _ => '审核通过',
      };
    }
    return switch (item.status) {
      'pending_review' => '待审核',
      'rejected' => '审核未通过',
      'pending' => '待领取（历史订单）',
      'claimed' => '已领取',
      'completed' => '已完成',
      'cancelled' => '已取消',
      _ => item.status.isEmpty ? '未知状态' : item.status,
    };
  }

  String _shippingSummary(
    AdminStoreOrderShipping shipping,
    String fulfillmentStatus,
  ) {
    if (fulfillmentStatus == 'shipped' &&
        shipping.carrier.isNotEmpty &&
        shipping.trackingNo.isNotEmpty) {
      return '物流：${shipping.carrier} ${shipping.trackingNo}';
    }
    final phone = shipping.maskedPhone.isEmpty
        ? shipping.phone
        : shipping.maskedPhone;
    final address = shipping.maskedAddress.isEmpty
        ? shipping.fullAddress
        : shipping.maskedAddress;
    return '收货：${shipping.maskedName.isEmpty ? shipping.recipientName : shipping.maskedName} · $phone · $address';
  }
}

class StoreOrderReviewDetailScreen extends StatefulWidget {
  const StoreOrderReviewDetailScreen({
    super.key,
    required this.repository,
    required this.orderId,
    this.onOpenUserActivity,
    this.onFeedback,
  });

  final PlatformRepository repository;
  final String orderId;
  final StoreOrderUserActivityCallback? onOpenUserActivity;
  final ValueChanged<String>? onFeedback;

  @override
  State<StoreOrderReviewDetailScreen> createState() =>
      _StoreOrderReviewDetailScreenState();
}

class _StoreOrderReviewDetailScreenState
    extends State<StoreOrderReviewDetailScreen> {
  late Future<AdminStoreOrderDetail> _future;
  final List<AdminStoreRewardContent> _rewardItems =
      <AdminStoreRewardContent>[];
  final Set<String> _invalidTransactionIds = <String>{};
  final TextEditingController _reasonController = TextEditingController();
  String? _rewardNextCursor;
  String? _rewardError;
  bool _rewardLoading = true;
  bool _rewardLoadingMore = false;
  bool _rewardHasMore = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getStoreOrder(widget.orderId);
    _loadRewardFirstPage();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadRewardFirstPage() async {
    setState(() {
      _rewardLoading = true;
      _rewardLoadingMore = false;
      _rewardError = null;
      _rewardItems.clear();
      _invalidTransactionIds.clear();
      _rewardNextCursor = null;
      _rewardHasMore = false;
    });
    try {
      final page = await widget.repository.getStoreOrderRewardContentPage(
        widget.orderId,
      );
      if (!mounted) return;
      setState(() {
        _rewardItems.addAll(page.items);
        _rewardNextCursor = page.nextCursor;
        _rewardHasMore = page.hasMore;
        _rewardLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rewardLoading = false;
        _rewardError = '$error';
      });
    }
  }

  Future<void> _loadMoreRewards() async {
    final cursor = _rewardNextCursor;
    if (_rewardLoadingMore ||
        !_rewardHasMore ||
        cursor == null ||
        cursor.isEmpty) {
      return;
    }
    setState(() => _rewardLoadingMore = true);
    try {
      final page = await widget.repository.getStoreOrderRewardContentPage(
        widget.orderId,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        _rewardItems.addAll(page.items);
        _rewardNextCursor = page.nextCursor;
        _rewardHasMore = page.hasMore;
        _rewardLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rewardLoadingMore = false;
        _rewardError = '$error';
      });
    }
  }

  int _baseEligiblePoints(AdminStoreOrderDetail order) {
    // 兼容尚未返回资格字段的旧服务端；正式接口始终使用申请时快照计算。
    if (!order.hasBalanceAtSubmit) {
      return order.userPoints;
    }
    return order.eligiblePointsAtSubmit;
  }

  int get _newInvalidatedPoints => _rewardItems
      .where(
        (item) => !item.invalidated && _invalidTransactionIds.contains(item.id),
      )
      .fold(0, (sum, item) => sum + item.points);

  int _effectivePoints(AdminStoreOrderDetail order) =>
      _baseEligiblePoints(order) - _newInvalidatedPoints;

  Future<void> _review(AdminStoreOrderDetail order, String decision) async {
    final reason = _reasonController.text.trim();
    if (decision == 'reject' && reason.isEmpty) {
      widget.onFeedback?.call('审核不通过时请填写原因');
      return;
    }
    if (_busy) return;
    final confirmed = await _confirmReview(order, decision, reason);
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.repository.reviewStoreOrder(
        id: order.id,
        decision: decision,
        reason: reason,
        invalidTransactionIds: _invalidTransactionIds.toList(),
      );
      widget.onFeedback?.call(decision == 'approve' ? '兑换申请已通过' : '兑换申请已拒绝');
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      widget.onFeedback?.call('审核失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ship(AdminStoreOrderDetail order) async {
    if (_busy) return;
    final payload = await _confirmShip(order);
    if (!mounted || payload == null) return;
    setState(() => _busy = true);
    try {
      await widget.repository.shipStoreOrder(
        id: order.id,
        carrier: payload.carrier,
        trackingNo: payload.trackingNo,
      );
      widget.onFeedback?.call('发货信息已提交');
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      widget.onFeedback?.call('发货失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmReview(
    AdminStoreOrderDetail order,
    String decision,
    String reason,
  ) {
    final approving = decision == 'approve';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approving ? '确认通过兑换申请？' : '确认拒绝兑换申请？'),
        content: Text(
          approving
              ? '用户：${_displayName(order)}\n商品：${order.productName}\n将扣除：${order.points} 积分'
              : '用户：${_displayName(order)}\n商品：${order.productName}\n拒绝原因：$reason',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(approving ? '确认通过' : '确认拒绝'),
          ),
        ],
      ),
    );
  }

  Future<({String carrier, String trackingNo})?> _confirmShip(
    AdminStoreOrderDetail order,
  ) => showDialog<({String carrier, String trackingNo})>(
    context: context,
    builder: (context) =>
        _ShipOrderDialog(order: order, displayName: _displayName(order)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          '兑换申请详情',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: FutureBuilder<AdminStoreOrderDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text('申请详情加载失败'));
          }
          final order = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
            children: [
              _detailCard([
                _detailRow('申请人', _displayName(order)),
                _detailRow('商品', order.productName),
                _detailRow('需要积分', '${order.points}'),
                _detailRow(
                  '申请时积分',
                  '${order.hasBalanceAtSubmit ? order.balanceAtSubmit : order.userPoints}',
                ),
                _detailRow('当前积分', '${order.userPoints}'),
                _detailRow('历史无效积分', '${order.historicalInvalidatedPoints}'),
                _detailRow('申请时有效积分', '${_baseEligiblePoints(order)}'),
                if (!order.balanceSnapshotTrusted)
                  _detailRow('积分快照', '历史快照待校准，仅供审核参考'),
                _detailRow(
                  '冻结 / 可用',
                  '${order.reservedPoints} / ${order.availablePoints}',
                ),
                _detailRow(
                  '申请时间',
                  '${relativeTimeLabel(order.createdAt)} · ${_formatDateTime(order.createdAt)}',
                ),
                _detailRow('订单状态', _statusLabel(order)),
                _detailRow('履约状态', _fulfillmentLabel(order.fulfillmentStatus)),
                if (order.reviewedAt != null)
                  _detailRow('审核时间', _formatDateTime(order.reviewedAt!)),
                if (order.reviewedAt != null)
                  _detailRow(
                    '审核人',
                    order.reviewedBy.isEmpty ? '管理员' : order.reviewedBy,
                  ),
                if (order.invalidatedPoints > 0)
                  _detailRow(
                    '本次无效奖励',
                    '${order.invalidatedCount} 笔 / ${order.invalidatedPoints} 积分',
                  ),
                if (order.shippedAt != null)
                  _detailRow('发货时间', _formatDateTime(order.shippedAt!)),
                if (order.completedAt != null)
                  _detailRow('完成时间', _formatDateTime(order.completedAt!)),
              ]),
              const SizedBox(height: 12),
              if (order.shipping != null) ...[
                _shippingCard(order),
                const SizedBox(height: 12),
              ],
              if (order.pointSources.isNotEmpty) ...[
                _pointSourceCard(order.pointSources, order),
                const SizedBox(height: 12),
              ] else ...[
                _activityCard(order),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text('取消与售后'),
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StoreOrderAftercareScreen(
                            admin: true,
                            load: () =>
                                widget.repository.storeAftercare(order.id),
                            submit: (body, key) => widget.repository
                                .reverseStoreOrder(order.id, body, key),
                            onChanged: () {
                              if (mounted) {
                                setState(
                                  () => _future = widget.repository
                                      .getStoreOrder(widget.orderId),
                                );
                              }
                            },
                          ),
                        ),
                      ),
              ),
              _rewardContentSection(),
              const SizedBox(height: 12),
              if (order.status == 'pending_review') _reviewCard(order),
              if (order.status != 'pending_review' &&
                  order.reviewReason.isNotEmpty)
                _detailCard([_detailRow('审核说明', order.reviewReason)]),
            ],
          );
        },
      ),
      bottomNavigationBar: FutureBuilder<AdminStoreOrderDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              snapshot.data == null) {
            return const SizedBox.shrink();
          }
          final order = snapshot.data!;
          if (order.status == 'pending_review') {
            return _reviewActionBar(order);
          }
          if (order.status == 'approved' &&
              order.fulfillmentStatus == 'ready_to_ship') {
            return _shipActionBar(order);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _activityCard(AdminStoreOrderDetail order) {
    return _detailCard([_activityActions(order)]);
  }

  Widget _shippingCard(AdminStoreOrderDetail order) {
    final shipping = order.shipping;
    if (shipping == null) return const SizedBox.shrink();
    return _detailCard([
      const Text('收货与物流', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      _detailRow('收件人', shipping.recipientName),
      _detailRow('手机号', shipping.phone),
      _detailRow('收货地址', shipping.fullAddress),
      if (shipping.submittedAt != null)
        _detailRow('提交时间', _formatDateTime(shipping.submittedAt!)),
      if (shipping.carrier.isNotEmpty || shipping.trackingNo.isNotEmpty) ...[
        const Divider(height: 18),
        _detailRow('物流公司', shipping.carrier),
        _detailRow('快递单号', shipping.trackingNo),
      ],
    ]);
  }

  Widget _pointSourceCard(
    List<StorePointSource> sources,
    AdminStoreOrderDetail order,
  ) {
    return _detailCard([
      const Text('兑换积分构成', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      _activityActions(order),
      const SizedBox(height: 12),
      for (final source in sources)
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              Expanded(child: Text(_sourceLabel(source.source))),
              Text(
                '${source.eligiblePoints} 分 / ${source.points} 分 · ${source.count} 笔',
                style: TextStyle(
                  color: source.invalidPoints > 0
                      ? AppTheme.orange
                      : AppTheme.textPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 3),
      const Text(
        '发帖和评论需要人工核验；点赞及其他正常积分不需要逐笔核验。',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    ]);
  }

  Widget _activityActions(AdminStoreOrderDetail order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('查看申请人的内容', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onOpenUserActivity == null
                    ? null
                    : () => widget.onOpenUserActivity!(order.userId, 0),
                icon: const Icon(Icons.article_outlined, size: 17),
                label: const Text('查看他的发帖'),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onOpenUserActivity == null
                    ? null
                    : () => widget.onOpenUserActivity!(order.userId, 1),
                icon: const Icon(Icons.chat_bubble_outline, size: 17),
                label: const Text('查看他的评论'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rewardContentSection() {
    if (_rewardLoading) {
      return _detailCard([
        const Text('获得积分的内容记录', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const LinearProgressIndicator(),
      ]);
    }
    if (_rewardError != null) {
      return _detailCard([
        const Text('获得积分的内容记录', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          '积分内容记录加载失败，请稍后重试。',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _loadRewardFirstPage,
          child: const Text('重新加载'),
        ),
      ]);
    }
    if (_rewardItems.isEmpty) {
      return _detailCard([
        const Text('获得积分的内容记录', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          '暂时没有可追溯的发帖或评论奖励流水。',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ]);
    }
    return _detailCard([
      const Text('获得积分的内容记录', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text(
        '以下内容按申请提交时的实际积分流水关联；删除、编辑内容会优先显示。勾选后，该笔奖励不会计入兑换资格。',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 6),
      for (final item in _rewardItems) _rewardContentTile(item),
      if (_rewardHasMore) ...[
        const SizedBox(height: 4),
        Center(
          child: _rewardLoadingMore
              ? const CircularProgressIndicator(strokeWidth: 2)
              : OutlinedButton(
                  onPressed: _loadMoreRewards,
                  child: const Text('加载更多奖励'),
                ),
        ),
      ],
    ]);
  }

  Widget _rewardContentTile(AdminStoreRewardContent item) {
    final status = _rewardStatusLabel(item.currentStatus);
    final edited = item.editedSinceReward ? ' · 已编辑' : '';
    final excluded =
        item.invalidated || _invalidTransactionIds.contains(item.id);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Row(
        children: [
          Text(
            '+${item.points}',
            style: const TextStyle(
              color: AppTheme.mint,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(_sourceLabel(item.source))),
          Text(
            '${item.invalidated ? '已判定不可兑换' : status}$edited',
            style: TextStyle(
              color: item.invalidated || item.currentStatus != 'normal'
                  ? AppTheme.orange
                  : AppTheme.mint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      subtitle: Text(
        '${relativeTimeLabel(item.earnedAt)} · ${item.titleAtReward.isEmpty ? '查看内容' : item.titleAtReward}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
      ),
      children: [
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: excluded,
            onChanged: item.invalidated
                ? null
                : (value) {
                    setState(() {
                      if (value == true) {
                        _invalidTransactionIds.add(item.id);
                      } else {
                        _invalidTransactionIds.remove(item.id);
                      }
                    });
                  },
            title: Text(
              item.invalidated ? '已判定不计入兑换' : '不计入兑换',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: item.invalidated && item.invalidationReason.isNotEmpty
                ? Text(
                    '判定说明：${item.invalidationReason}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  )
                : null,
          ),
        ),
        if (!item.snapshotAvailable)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '该流水缺少历史内容快照，以下为当前内容。',
              style: TextStyle(color: AppTheme.orange, fontSize: 11),
            ),
          ),
        if (item.titleAtReward.isNotEmpty)
          _contentText(
            item.targetType == 'post' ? '获得积分时标题' : '所属帖子',
            item.titleAtReward,
          ),
        _contentText('获得积分时内容', item.contentAtReward),
        if (item.targetType == 'post' &&
            item.editedSinceReward &&
            item.currentTitle.isNotEmpty)
          _contentText('当前标题', item.currentTitle),
        if (item.editedSinceReward && item.currentContent.isNotEmpty)
          _contentText('当前内容', item.currentContent),
      ],
    );
  }

  Widget _reviewCard(AdminStoreOrderDetail order) {
    final effectivePoints = _effectivePoints(order);
    final enoughPoints = effectivePoints >= order.points;
    return _detailCard([
      const Text('核验结果', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      _detailRow('账户当前积分', '${order.userPoints}'),
      _detailRow(
        '申请时积分',
        '${order.hasBalanceAtSubmit ? order.balanceAtSubmit : order.userPoints}',
      ),
      _detailRow('历史无效积分', '${order.historicalInvalidatedPoints}'),
      _detailRow('本次新判定无效', '$_newInvalidatedPoints'),
      _detailRow('有效可兑换积分', '$effectivePoints'),
      _detailRow('兑换需要', '${order.points}'),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: enoughPoints ? AppTheme.softMint : AppTheme.softRose,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          enoughPoints
              ? '✓ 有效积分满足兑换条件'
              : '✕ 有效积分不足 ${order.points - effectivePoints} 分',
          style: TextStyle(
            color: enoughPoints ? AppTheme.mint : AppTheme.pink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Text('管理员判断', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      TextField(
        controller: _reasonController,
        maxLines: 4,
        maxLength: 1000,
        decoration: const InputDecoration(
          hintText: '审核说明；拒绝时必填，例如：存在较多无实质内容的刷屏回复',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 70),
    ]);
  }

  Widget _reviewActionBar(AdminStoreOrderDetail order) {
    final enoughPoints = _effectivePoints(order) >= order.points;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _review(order, 'reject'),
                child: const Text('审核不通过'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed:
                    _busy ||
                        _rewardLoading ||
                        _rewardError != null ||
                        !enoughPoints
                    ? null
                    : () => _review(order, 'approve'),
                child: Text(_busy ? '提交中…' : '审核通过'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shipActionBar(AdminStoreOrderDetail order) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: FilledButton.icon(
          onPressed: _busy ? null : () => _ship(order),
          icon: const Icon(Icons.local_shipping_outlined, size: 18),
          label: Text(_busy ? '提交中...' : '确认发货'),
        ),
      ),
    );
  }

  Widget _contentText(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label：',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: value.isEmpty ? '（暂无内容）' : value),
            ],
          ),
          style: const TextStyle(fontSize: 12, height: 1.45),
        ),
      ),
    );
  }

  Widget _detailCard(List<Widget> children) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
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

  String _displayName(AdminStoreOrder order) =>
      order.nickname.trim().isEmpty ? '@${order.username}' : order.nickname;

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  String _statusLabel(AdminStoreOrder order) {
    if (order.status == 'approved') {
      return switch (order.fulfillmentStatus) {
        'awaiting_address' => '审核通过 · 待填地址',
        'ready_to_ship' => '待发货',
        'return_requested' => '退货待审核',
        'refund_pending' => '待退款',
        'refunded' => '已退款',
        'shipped' => '已发货',
        'completed' => '已完成',
        'cancelled' => '已取消',
        _ => '审核通过',
      };
    }
    return switch (order.status) {
      'pending_review' => '待审核',
      'rejected' => '审核未通过',
      'pending' => '待领取（历史订单）',
      'claimed' => '已领取',
      'completed' => '已完成',
      'cancelled' => '已取消',
      _ => order.status.isEmpty ? '未知状态' : order.status,
    };
  }

  String _fulfillmentLabel(String value) => switch (value) {
    'none' => '未进入履约',
    'return_requested' => '退货待审核',
    'refund_pending' => '待退款',
    'refunded' => '已退款',
    'awaiting_address' => '待填写收货信息',
    'ready_to_ship' => '待发货',
    'shipped' => '已发货',
    'completed' => '已完成',
    'cancelled' => '已取消',
    _ => value.isEmpty ? '未进入履约' : value,
  };

  String _rewardStatusLabel(String value) => switch (value) {
    'normal' => '正常',
    'deleted' => '已删除',
    'unavailable' => '当前不可见',
    'missing' => '内容已不存在',
    _ => value.isEmpty ? '未知状态' : value,
  };

  String _sourceLabel(String value) => switch (value) {
    'post' => '发帖奖励',
    'comment' => '评论奖励',
    'like' => '点赞奖励',
    _ => value.isEmpty ? '其他积分' : value,
  };
}

class _ShipOrderDialog extends StatefulWidget {
  const _ShipOrderDialog({required this.order, required this.displayName});

  final AdminStoreOrderDetail order;
  final String displayName;

  @override
  State<_ShipOrderDialog> createState() => _ShipOrderDialogState();
}

class _ShipOrderDialogState extends State<_ShipOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _carrierController;
  late final TextEditingController _trackingController;

  @override
  void initState() {
    super.initState();
    _carrierController = TextEditingController(
      text: widget.order.shipping?.carrier ?? '',
    );
    _trackingController = TextEditingController(
      text: widget.order.shipping?.trackingNo ?? '',
    );
  }

  @override
  void dispose() {
    _carrierController.dispose();
    _trackingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认发货'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.displayName} · ${widget.order.productName}',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _carrierController,
              decoration: const InputDecoration(
                labelText: '物流公司',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '请填写物流公司' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _trackingController,
              decoration: const InputDecoration(
                labelText: '快递单号',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '请填写快递单号' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.of(context).pop((
              carrier: _carrierController.text.trim(),
              trackingNo: _trackingController.text.trim(),
            ));
          },
          child: const Text('确认发货'),
        ),
      ],
    );
  }
}
