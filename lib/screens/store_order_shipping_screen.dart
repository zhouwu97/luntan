import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/store_repository.dart';
import '../theme/app_theme.dart';

class StoreOrderShippingScreen extends StatefulWidget {
  const StoreOrderShippingScreen({
    super.key,
    required this.repository,
    required this.orderId,
  });

  final StoreRepository repository;
  final String orderId;

  @override
  State<StoreOrderShippingScreen> createState() =>
      _StoreOrderShippingScreenState();
}

class _StoreOrderShippingScreenState extends State<StoreOrderShippingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _recipientController = TextEditingController();
  final _phoneController = TextEditingController();
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _addressController = TextEditingController();

  late Future<StoreOrder> _future;
  bool _seeded = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.order(widget.orderId);
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _phoneController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _seed(StoreOrder order) {
    if (_seeded) return;
    _seeded = true;
    final shipping = order.shipping;
    if (shipping == null) return;
    _recipientController.text = shipping.recipientName;
    _phoneController.text = shipping.phone;
    _provinceController.text = shipping.province;
    _cityController.text = shipping.city;
    _districtController.text = shipping.district;
    _addressController.text = shipping.addressDetail;
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.repository.submitShipping(
        orderId: widget.orderId,
        recipientName: _recipientController.text.trim(),
        phone: _phoneController.text.trim(),
        province: _provinceController.text.trim(),
        city: _cityController.text.trim(),
        district: _districtController.text.trim(),
        addressDetail: _addressController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('收货信息已提交，等待管理员发货')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingApiMessage(error, fallback: '提交失败，请稍后重试')),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          '收货信息',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: FutureBuilder<StoreOrder>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _StateMessage(
              title: '订单加载失败',
              action: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _seeded = false;
                    _future = widget.repository.order(widget.orderId);
                  });
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新加载'),
              ),
            );
          }
          final order = snapshot.data!;
          _seed(order);
          if (!order.canEditShipping) {
            return _StateMessage(
              title: _lockedMessage(order),
              action: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('返回我的兑换'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.card_giftcard_outlined,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.productName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${order.points} 积分 · ${_statusLabel(order)}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _field(
                      controller: _recipientController,
                      label: '收件人',
                      icon: Icons.person_outline,
                      maxLength: 40,
                    ),
                    _field(
                      controller: _phoneController,
                      label: '手机号码',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      minLength: 5,
                      maxLength: 30,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            controller: _provinceController,
                            label: '省份',
                            icon: Icons.map_outlined,
                            maxLength: 40,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(
                            controller: _cityController,
                            label: '城市',
                            icon: Icons.location_city_outlined,
                            maxLength: 40,
                          ),
                        ),
                      ],
                    ),
                    _field(
                      controller: _districtController,
                      label: '区县',
                      icon: Icons.place_outlined,
                      required: false,
                      maxLength: 40,
                    ),
                    _field(
                      controller: _addressController,
                      label: '详细地址',
                      icon: Icons.home_outlined,
                      minLength: 2,
                      maxLength: 120,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '该信息仅用于本次兑换商品寄送，发货后将不能修改。',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(_submitting ? '提交中...' : '确认提交'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool required = true,
    int minLength = 1,
    int maxLength = 80,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
        ),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (!required && text.isEmpty) return null;
          final length = text.runes.length;
          if (length < minLength) return '请填写$label';
          if (length > maxLength) return '$label不能超过 $maxLength 个字';
          return null;
        },
      ),
    );
  }

  String _lockedMessage(StoreOrder order) {
    if (order.fulfillmentStatus == 'shipped') return '订单已发货，收货信息已锁定';
    if (order.fulfillmentStatus == 'completed') return '订单已完成，收货信息已锁定';
    return '当前订单暂不能填写收货信息';
  }

  String _statusLabel(StoreOrder order) => switch (order.fulfillmentStatus) {
    'awaiting_address' => '待填写收货信息',
    'ready_to_ship' => '待发货',
    'shipped' => '已发货',
    'completed' => '已完成',
    _ => '审核通过',
  };
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}
