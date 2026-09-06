import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import '../data/api/api_client.dart';

String storeFulfillmentLabel(String status) => switch (status) {
  'none' => '待审核',
  'awaiting_address' => '待填地址',
  'ready_to_ship' => '待发货',
  'shipped' => '已发货',
  'completed' => '已完成',
  'cancelled' => '已取消',
  'return_requested' => '退货待审核',
  'refund_pending' => '已同意退货 · 待退款',
  'refunded' => '已退款',
  _ => status,
};

class StoreOrderAftercareScreen extends StatefulWidget {
  const StoreOrderAftercareScreen({
    super.key,
    required this.load,
    required this.submit,
    this.admin = false,
    required this.onChanged,
  });
  final Future<Map<String, dynamic>> Function() load;
  final Future<void> Function(Map<String, dynamic> body, String key) submit;
  final bool admin;
  final VoidCallback onChanged;

  @override
  State<StoreOrderAftercareScreen> createState() =>
      _StoreOrderAftercareScreenState();
}

class _StoreOrderAftercareScreenState extends State<StoreOrderAftercareScreen> {
  late Future<Map<String, dynamic>> _future;
  final _reason = TextEditingController();
  final _carrier = TextEditingController();
  final _tracking = TextEditingController();
  final _keys = <String, String>{};
  bool _busy = false, _received = false, _restock = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _carrier.dispose();
    _tracking.dispose();
    super.dispose();
  }

  Future<void> _submit(String action) async {
    if (_busy) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = '请填写操作说明');
      return;
    }
    final body = <String, dynamic>{
      'action': action,
      'reason': _reason.text.trim(),
    };
    if (action == 'return_shipping') {
      if (_carrier.text.trim().isEmpty || _tracking.text.trim().isEmpty) {
        setState(() => _error = '请填写回寄物流公司和单号');
        return;
      }
      body.addAll({
        'carrier': _carrier.text.trim(),
        'tracking_no': _tracking.text.trim(),
      });
    }
    if (action == 'refund') {
      body.addAll({'return_received': _received, 'restock': _restock});
    }
    final fingerprint = jsonEncode(body);
    final key = _keys.putIfAbsent(
      fingerprint,
      () => List.generate(
        24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(body, key);
      _keys.remove(fingerprint);
      if (!mounted) return;
      widget.onChanged();
      setState(() {
        _future = widget.load();
        _reason.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('订单已更新')));
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingApiMessage(error, fallback: '操作失败，请重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('取消与售后')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _future = widget.load()),
              child: const Text('售后信息加载失败，点击重试'),
            ),
          );
        }
        final data = snapshot.data!;
        final status = data['status'];
        final fs = '${data['fulfillment_status']}';
        final canCancel =
            status == 'pending_review' ||
            (status == 'approved' &&
                ['awaiting_address', 'ready_to_ship'].contains(fs));
        final canReturn =
            status == 'approved' && ['shipped', 'completed'].contains(fs);
        final canReview = widget.admin && fs == 'return_requested';
        final pendingRefund = fs == 'refund_pending';
        final canAct = canCancel || canReturn || canReview || pendingRefund;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              status == 'rejected' ? '审核未通过' : storeFulfillmentLabel(fs),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if ((data['refunded_points'] as num? ?? 0) > 0)
              Text('已返还 ${data['refunded_points']} 积分'),
            for (final entry in {
              'reason': '最新说明',
              'return_instructions': '回寄要求',
              'carrier': '回寄物流',
              'tracking_no': '回寄单号',
            }.entries)
              if ('${data[entry.key] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText('${entry.value}：${data[entry.key]}'),
                ),
            if (canAct) ...[
              const SizedBox(height: 20),
              TextField(
                controller: _reason,
                enabled: !_busy,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: canReview ? '审核说明（同意时填写回寄地址及要求）' : '操作说明（必填）',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (pendingRefund && !widget.admin) ...[
                TextField(
                  controller: _carrier,
                  enabled: !_busy,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: '回寄物流公司'),
                ),
                TextField(
                  controller: _tracking,
                  enabled: !_busy,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: '回寄物流单号'),
                ),
              ],
              if (pendingRefund && widget.admin) ...[
                CheckboxListTile(
                  value: _received,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _received = v ?? false),
                  title: const Text('已实际收到退回商品'),
                ),
                CheckboxListTile(
                  value: _restock,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _restock = v ?? false),
                  title: const Text('商品完好，可重新入库'),
                ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (canCancel)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _submit('cancel'),
                      child: const Text('取消订单并返还已扣积分'),
                    ),
                  if (canReturn)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _submit('request_return'),
                      child: const Text('申请退货'),
                    ),
                  if (canReview) ...[
                    FilledButton(
                      onPressed: _busy ? null : () => _submit('approve_return'),
                      child: const Text('同意退货'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _submit('reject_return'),
                      child: const Text('拒绝退货'),
                    ),
                  ],
                  if (pendingRefund && !widget.admin)
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _submit('return_shipping'),
                      child: const Text('提交回寄物流'),
                    ),
                  if (pendingRefund && widget.admin)
                    FilledButton(
                      onPressed: _busy || !_received
                          ? null
                          : () => _submit('refund'),
                      child: const Text('确认退货并返还积分'),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}
