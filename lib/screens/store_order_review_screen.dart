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
  String _selectedStatus = 'pending_review';
  int _requestGeneration = 0;

  static const _statusFilters = <({String value, String label})>[
    (value: 'pending_review', label: '待审核'),
    (value: 'awaiting_address', label: '待填地址'),
    (value: 'ready_to_ship', label: '待发货'),
    (value: 'shipped', label: '已发货'),
    (value: 'completed', label: '已完成'),
    (value: 'rejected', label: '已拒绝'),
    (value: 'all', label: '全部'),
  ];

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_requestGeneration;
    final requestStatus = _selectedStatus;

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
      final page = await widget.repository.listStoreOrderPage(
        status: requestStatus,
      );
      if (!mounted ||
          generation != _requestGeneration ||
          requestStatus != _selectedStatus) {
        return;
      }
      setState(() {
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          generation != _requestGeneration ||
          requestStatus != _selectedStatus) {
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
    final requestStatus = _selectedStatus;

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
          requestStatus != _selectedStatus ||
          cursor != _nextCursor) {
        return;
      }
      setState(() {
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted ||
          generation != _requestGeneration ||
          requestStatus != _selectedStatus) {
        return;
      }
      setState(() {
        _loadingMore = false;
        _loadMoreError = '$error';
      });
    }
  }

  Future<void> _refresh() => _loadFirstPage();

  Future<void> _selectStatus(String status) async {
    if (status == _selectedStatus) return;
    setState(() => _selectedStatus = status);
    await _loadFirstPage();
  }

  Future<void> _openDetail(AdminStoreOrder item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => StoreOrderReviewDetailScreen(
          repository: widget.repository,
          orderId: item.id,
          onOpenUserActivity: widget.onOpenUserActivity,
          onFeedback: widget.onFeedback,
        ),
      ),
    );
    if (changed == true && mounted) {
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
          _buildStatusFilters(),
          Expanded(
            child: RefreshIndicator(onRefresh: _refresh, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: Row(
        children: [
          for (final filter in _statusFilters) ...[
            ChoiceChip(
              label: Text(filter.label),
              selected: filter.value == _selectedStatus,
              onSelected: (_) => _selectStatus(filter.value),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
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
        children: const [
          SizedBox(height: 180),
          Center(child: Text('当前没有符合条件的兑换申请')),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.softRose,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.card_giftcard_outlined,
                  color: AppTheme.pink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.productName} · ${item.points} 积分',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '订单状态：${_statusLabel(item)}',
                      style: TextStyle(
                        color: item.status == 'rejected'
                            ? AppTheme.orange
                            : AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.shipping != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _shippingSummary(
                          item.shipping!,
                          item.fulfillmentStatus,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      '申请时间 ${relativeTimeLabel(item.createdAt)} · 当前积分 ${item.userPoints}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (item.status != 'pending_review' &&
                        item.reviewedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '审核于 ${relativeTimeLabel(item.reviewedAt!)} · ${item.reviewedBy.isEmpty ? '管理员' : item.reviewedBy}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (item.invalidatedPoints > 0)
                      Text(
                        '已剔除 ${item.invalidatedCount} 笔奖励 · ${item.invalidatedPoints} 积分',
                        style: const TextStyle(
                          color: AppTheme.orange,
                          fontSize: 11,
                        ),
                      ),
                    if (item.reviewReason.trim().isNotEmpty)
                      Text(
                        '审核理由：${item.reviewReason}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(AdminStoreOrder item) {
    if (item.status == 'approved') {
      return switch (item.fulfillmentStatus) {
        'awaiting_address' => '审核通过 · 待填地址',
        'ready_to_ship' => '待发货',
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
