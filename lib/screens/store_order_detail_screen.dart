import 'package:flutter/material.dart';
import '../data/api/api_client.dart';
import '../data/api/store_repository.dart';
import 'store_order_aftercare_screen.dart';
import 'store_order_shipping_screen.dart';

class StoreOrderDetailScreen extends StatefulWidget {
  const StoreOrderDetailScreen({
    super.key,
    required this.repository,
    required this.orderId,
  });
  final StoreRepository repository;
  final String orderId;
  @override
  State<StoreOrderDetailScreen> createState() => _StoreOrderDetailScreenState();
}

class _StoreOrderDetailScreenState extends State<StoreOrderDetailScreen> {
  late Future<StoreOrder> _future;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _future = widget.repository.order(widget.orderId);
  }

  void _reload() {
    if (mounted) {
      setState(() => _future = widget.repository.order(widget.orderId));
    }
  }

  Future<void> _complete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认已收到商品？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认已收到'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.completeOrder(widget.orderId);
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('兑换订单详情')),
    body: FutureBuilder<StoreOrder>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: TextButton(
              onPressed: _reload,
              child: const Text('订单加载失败，点击重试'),
            ),
          );
        }
        final order = snapshot.data!;
        final shipping = order.shipping;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              order.productName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              order.status == 'rejected'
                  ? '审核未通过'
                  : storeFulfillmentLabel(order.fulfillmentStatus),
            ),
            Text('${order.points} 积分'),
            if (order.reviewReason.isNotEmpty)
              Text('审核说明：${order.reviewReason}'),
            if (shipping != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                '${shipping.recipientName} ${shipping.phone}\n${shipping.fullAddress}',
              ),
              if (shipping.trackingNo.isNotEmpty)
                SelectableText(
                  '物流：${shipping.carrier}\n单号：${shipping.trackingNo}',
                ),
            ],
            const SizedBox(height: 20),
            if (order.canEditShipping)
              FilledButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => StoreOrderShippingScreen(
                        repository: widget.repository,
                        orderId: order.id,
                      ),
                    ),
                  );
                  _reload();
                },
                child: Text(order.needsShipping ? '填写收货信息' : '修改收货信息'),
              ),
            if (order.canComplete)
              FilledButton(
                onPressed: _busy ? null : _complete,
                child: const Text('确认已收到'),
              ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StoreOrderAftercareScreen(
                    load: () => widget.repository.aftercare(order.id),
                    submit: (body, key) =>
                        widget.repository.reverseOrder(order.id, body, key),
                    onChanged: _reload,
                  ),
                ),
              ),
              child: const Text('取消与售后'),
            ),
          ],
        );
      },
    ),
  );
}
