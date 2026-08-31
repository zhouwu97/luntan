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
  late Future<List<AdminStoreOrder>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listStoreOrders();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repository.listStoreOrders();
    });
    await _future;
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
      setState(() {
        _future = widget.repository.listStoreOrders();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          '兑换审核',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AdminStoreOrder>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return ListView(
                children: const [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  const SizedBox(height: 120),
                  const Center(child: Text('兑换申请加载失败')),
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton(
                      onPressed: () => setState(
                        () => _future = widget.repository.listStoreOrders(),
                      ),
                      child: const Text('重新加载'),
                    ),
                  ),
                ],
              );
            }
            final items = snapshot.data ?? const <AdminStoreOrder>[];
            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 180),
                  Center(child: Text('当前没有待审核的兑换申请')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _StoreOrderListTile(
                item: items[index],
                onTap: () => _openDetail(items[index]),
              ),
            );
          },
        ),
      ),
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
                      '申请于 ${relativeTimeLabel(item.createdAt)} · 当前积分 ${item.userPoints}',
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
  final TextEditingController _reasonController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getStoreOrder(widget.orderId);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _review(AdminStoreOrderDetail order, String decision) async {
    final reason = _reasonController.text.trim();
    if (decision == 'reject' && reason.isEmpty) {
      widget.onFeedback?.call('审核不通过时请填写原因');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.reviewStoreOrder(
        id: order.id,
        decision: decision,
        reason: reason,
      );
      widget.onFeedback?.call(decision == 'approve' ? '兑换申请已通过' : '兑换申请已拒绝');
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      widget.onFeedback?.call('审核失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
                _detailRow('当前积分', '${order.userPoints}'),
                _detailRow('审核中冻结', '${order.reservedPoints}'),
                _detailRow('可用积分', '${order.availablePoints}'),
                _detailRow('申请时间', relativeTimeLabel(order.createdAt)),
                _detailRow('订单状态', _statusLabel(order.status)),
              ]),
              const SizedBox(height: 12),
              _activityCard(order),
              const SizedBox(height: 12),
              if (order.pointSources.isNotEmpty) ...[
                _pointSourceCard(order.pointSources),
                const SizedBox(height: 12),
              ],
              if (order.status == 'pending_review') _reviewCard(order),
              if (order.status != 'pending_review' &&
                  order.reviewReason.isNotEmpty)
                _detailCard([_detailRow('审核说明', order.reviewReason)]),
            ],
          );
        },
      ),
    );
  }

  Widget _activityCard(AdminStoreOrderDetail order) {
    return _detailCard([
      const Text('查看申请人的内容', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      const Text(
        '请结合他的发帖和评论，判断本次兑换是否符合积分规则。不要给单条内容增加水贴标签。',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 10),
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
    ]);
  }

  Widget _pointSourceCard(List<StorePointSource> sources) {
    return _detailCard([
      const Text('积分来源参考', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      for (final source in sources)
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              Expanded(child: Text(_sourceLabel(source.source))),
              Text('${source.points} 分 · ${source.count} 笔'),
            ],
          ),
        ),
    ]);
  }

  Widget _reviewCard(AdminStoreOrderDetail order) {
    return _detailCard([
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
      const SizedBox(height: 5),
      Row(
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
              onPressed: _busy ? null : () => _review(order, 'approve'),
              child: Text(_busy ? '提交中…' : '审核通过'),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _detailCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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

  String _statusLabel(String value) => switch (value) {
    'pending_review' => '待审核',
    'approved' => '审核通过 · 待领取',
    'rejected' => '审核未通过',
    'pending' => '待领取（历史订单）',
    'claimed' => '已领取',
    'completed' => '已完成',
    'cancelled' => '已取消',
    _ => value.isEmpty ? '未知状态' : value,
  };

  String _sourceLabel(String value) => switch (value) {
    'post' => '发帖奖励',
    'comment' => '评论奖励',
    'like' => '点赞奖励',
    _ => value.isEmpty ? '其他积分' : value,
  };
}
