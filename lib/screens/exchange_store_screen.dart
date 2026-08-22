import 'package:flutter/material.dart';

import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';

class ExchangeStoreScreen extends StatelessWidget {
  const ExchangeStoreScreen({super.key, required this.store});

  final ForumStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('兑换商店')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(24)), child: Row(children: [const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 38), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('校园周边兑换', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 5), const Text('积分只用于社区周边，不接现金、充值、提现和红包。', style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 12, height: 1.4))])), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)), child: Text('${store.points} 积分', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))])),
            const SizedBox(height: 20),
            const Text('全部商品', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: storeProducts.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .86), itemBuilder: (_, index) => _ProductCard(product: storeProducts[index], onRedeem: () => _redeem(context, storeProducts[index]))),
          ],
        ),
      ),
    );
  }

  void _redeem(BuildContext context, StoreProduct product) {
    final success = store.redeem(product);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? '已兑换${product.name}，请留意领取通知' : '积分不足，再攒一攒就可以兑换啦')));
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onRedeem});

  final StoreProduct product;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Color(product.color), borderRadius: BorderRadius.circular(15)),
              child: Text(product.emoji, style: const TextStyle(fontSize: 52)),
            ),
          ),
          const SizedBox(height: 10),
          Text(product.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(product.description, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(child: Text('${product.points} 积分', style: const TextStyle(color: AppTheme.orange, fontSize: 12, fontWeight: FontWeight.w800))),
              SizedBox(
                height: 30,
                child: FilledButton(
                  onPressed: onRedeem,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
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
