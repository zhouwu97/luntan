import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../data/api/api_client.dart';
import '../data/api/store_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/points_wallet_card.dart';
import 'points_screen.dart';

class ExchangeStoreScreen extends StatelessWidget {
  const ExchangeStoreScreen({super.key, this.store, this.apiRepository});

  final ForumStore? store;
  final StoreRepository? apiRepository;

  @override
  Widget build(BuildContext context) {
    if (apiRepository != null) {
      return _ApiExchangeStoreScreen(repository: apiRepository!);
    }
    final localStore = store!;
    return AnimatedBuilder(
      animation: localStore,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('兑换商店')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            PointsWalletCard(
              balance: localStore.points,
              onOpenDetails: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PointsCenterScreen(store: localStore),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              '全部商品',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: storeProducts.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: .86,
              ),
              itemBuilder: (_, index) => _ProductCard(
                product: storeProducts[index],
                onRedeem: () => _redeem(context, storeProducts[index]),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '我的兑换',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (localStore.redeemedProducts.isEmpty)
              const Text(
                '还没有兑换记录',
                style: TextStyle(color: AppTheme.textSecondary),
              )
            else
              ...localStore.redeemedProducts.map(
                (product) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.card_giftcard_outlined,
                    color: AppTheme.primary,
                  ),
                  title: Text(product.name),
                  subtitle: Text('${product.points} 积分'),
                  trailing: const Text('待审核'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _redeem(BuildContext context, StoreProduct product) {
    final success = store!.redeem(product);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? '兑换申请已提交，等待管理员审核' : '积分不足，再攒一攒就可以兑换啦')),
    );
  }
}

class _ApiExchangeStoreScreen extends StatefulWidget {
  const _ApiExchangeStoreScreen({required this.repository});
  final StoreRepository repository;
  @override
  State<_ApiExchangeStoreScreen> createState() =>
      _ApiExchangeStoreScreenState();
}

class _ApiExchangeStoreScreenState extends State<_ApiExchangeStoreScreen> {
  late Future<List<ApiStoreProduct>> productsFuture;
  late Future<int> balanceFuture;
  late Future<List<StoreOrder>> ordersFuture;

  final Set<String> _redeeming = <String>{};
  // 兑换幂等键按商品持久到请求成功为止，弱网重试时复用同一个键，
  // 避免服务端把重试当成新订单重复扣积分。
  final Map<String, String> _pendingRedeemKeys = <String, String>{};

  @override
  void initState() {
    super.initState();
    productsFuture = widget.repository.products();
    balanceFuture = widget.repository.balance();
    ordersFuture = widget.repository.orders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('兑换商店')),
      body: FutureBuilder<List<ApiStoreProduct>>(
        future: productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('商店加载失败：${snapshot.error}'));
          }
          final items = snapshot.data ?? const <ApiStoreProduct>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              FutureBuilder<int>(
                future: balanceFuture,
                builder: (context, balance) => PointsWalletCard(
                  balance: balance.data ?? 0,
                  balanceLoading:
                      balance.connectionState != ConnectionState.done,
                  onOpenDetails: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PointsCenterScreen(
                          apiRepository: widget.repository,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '全部商品',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: .86,
                ),
                itemBuilder: (_, index) => _ApiProductCard(
                  product: items[index],
                  onRedeem: () => _redeem(items[index]),
                  busy: _redeeming.contains(items[index].id),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '我的兑换',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<StoreOrder>>(
                future: ordersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  final orders = snapshot.data ?? const <StoreOrder>[];
                  if (orders.isEmpty) {
                    return const Text(
                      '还没有兑换记录',
                      style: TextStyle(color: AppTheme.textSecondary),
                    );
                  }
                  return Column(
                    children: orders
                        .map(
                          (order) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.card_giftcard_outlined,
                              color: AppTheme.primary,
                            ),
                            title: Text(order.productName),
                            subtitle: Text(
                              '${order.points} 积分 · ${relativeTimeLabel(order.createdAt)}',
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_orderStatus(order.status)),
                                if (order.status == 'rejected' &&
                                    order.reviewReason.isNotEmpty)
                                  Text(
                                    order.reviewReason,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _redeem(ApiStoreProduct product) async {
    if (_redeeming.contains(product.id)) return;
    setState(() => _redeeming.add(product.id));
    try {
      final requestKey = _pendingRedeemKeys.putIfAbsent(
        product.id,
        () => sha256
            .convert(
              utf8.encode(
                '${product.id}:${DateTime.now().microsecondsSinceEpoch}',
              ),
            )
            .toString(),
      );
      await widget.repository.redeem(product.id, idempotencyKey: requestKey);
      _pendingRedeemKeys.remove(product.id);
      if (!mounted) return;
      setState(() {
        productsFuture = widget.repository.products();
        balanceFuture = widget.repository.balance();
        ordersFuture = widget.repository.orders();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('兑换申请已提交，等待管理员审核')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingApiMessage(error, fallback: '兑换失败，请稍后重试')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _redeeming.remove(product.id));
    }
  }

  String _orderStatus(String status) => switch (status) {
    'pending_review' => '待审核',
    'approved' => '审核通过 · 待领取',
    'rejected' => '审核未通过',
    'pending' => '待领取',
    'claimed' => '已领取',
    'completed' => '已完成',
    'cancelled' => '已取消',
    _ => status.isEmpty ? '处理中' : status,
  };
}

class _ApiProductCard extends StatelessWidget {
  const _ApiProductCard({
    required this.product,
    required this.onRedeem,
    this.busy = false,
  });
  final ApiStoreProduct product;
  final VoidCallback onRedeem;
  final bool busy;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTheme.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(product.color),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(product.emoji, style: const TextStyle(fontSize: 52)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          product.name,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          product.description,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: Text(
                '${product.points} 积分',
                style: const TextStyle(
                  color: AppTheme.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(
              height: 30,
              child: FilledButton(
                onPressed: busy ? null : onRedeem,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(
                  busy ? '兑换中…' : '兑换',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onRedeem});

  final StoreProduct product;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color(product.color),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(product.emoji, style: const TextStyle(fontSize: 52)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            product.name,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            product.description,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${product.points} 积分',
                  style: const TextStyle(
                    color: AppTheme.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(
                height: 30,
                child: FilledButton(
                  onPressed: onRedeem,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text('兑换', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
