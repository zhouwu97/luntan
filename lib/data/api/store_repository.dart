import 'api_client.dart';

class PointTransaction {
  const PointTransaction({
    required this.id,
    required this.source,
    required this.delta,
    required this.balanceAfter,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String source;
  final int delta;
  final int balanceAfter;
  final String reason;
  final DateTime createdAt;
}

class PointsOverview {
  const PointsOverview({required this.balance, required this.transactions});

  final int balance;
  final List<PointTransaction> transactions;
}

class ApiStoreProduct {
  const ApiStoreProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.points,
    required this.color,
    required this.redeemedCount,
    this.imageUrl = '',
  });
  final String id;
  final String name;
  final String description;
  final String emoji;
  final int points;
  final int color;
  final int redeemedCount;
  final String imageUrl;
}

class StoreOrder {
  const StoreOrder({
    required this.id,
    required this.productId,
    required this.productName,
    required this.points,
    required this.status,
    required this.fulfillmentStatus,
    required this.createdAt,
    this.reviewReason = '',
    this.reviewedAt,
    this.shippedAt,
    this.completedAt,
    this.shipping,
  });

  final String id;
  final String productId;
  final String productName;
  final int points;
  final String status;
  final String fulfillmentStatus;
  final DateTime createdAt;
  final String reviewReason;
  final DateTime? reviewedAt;
  final DateTime? shippedAt;
  final DateTime? completedAt;
  final StoreOrderShipping? shipping;

  bool get needsShipping =>
      status == 'approved' && fulfillmentStatus == 'awaiting_address';

  bool get canEditShipping =>
      status == 'approved' &&
      (fulfillmentStatus == 'awaiting_address' ||
          fulfillmentStatus == 'ready_to_ship');
}

class StoreOrderShipping {
  const StoreOrderShipping({
    required this.recipientName,
    required this.phone,
    required this.province,
    required this.city,
    required this.district,
    required this.addressDetail,
    this.carrier = '',
    this.trackingNo = '',
    this.maskedName = '',
    this.maskedPhone = '',
    this.maskedAddress = '',
    this.submittedAt,
    this.updatedAt,
  });

  final String recipientName;
  final String phone;
  final String province;
  final String city;
  final String district;
  final String addressDetail;
  final String carrier;
  final String trackingNo;
  final String maskedName;
  final String maskedPhone;
  final String maskedAddress;
  final DateTime? submittedAt;
  final DateTime? updatedAt;

  String get fullAddress => [
    province,
    city,
    district,
    addressDetail,
  ].where((part) => part.trim().isNotEmpty).join(' ');
}

class StoreRepository {
  StoreRepository(this._client);
  final ApiClient _client;

  Future<List<ApiStoreProduct>> products() async {
    final value = await _client.getJson('/api/v1/store/products');
    final raw = value['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) {
      final data = Map<String, dynamic>.from(item);
      return ApiStoreProduct(
        id: _string(data['id']),
        name: _string(data['name']),
        description: _string(data['description']),
        emoji: _string(data['emoji']),
        points: _int(data['points']),
        color: _int(data['color']),
        redeemedCount: _int(data['redeemed_count']),
        imageUrl: _string(data['image_url']),
      );
    }).toList();
  }

  Future<int> balance() async {
    final value = await overview();
    return value.balance;
  }

  Future<PointsOverview> overview() async {
    final value = await _client.getJson('/api/v1/me/points');
    final raw = value['transactions'];
    final now = DateTime.now().toUtc();
    final transactions = raw is List
        ? raw.whereType<Map>().map((item) {
            final data = Map<String, dynamic>.from(item);
            return PointTransaction(
              id: _string(data['id']),
              source: _string(data['source']),
              delta: _int(data['delta']),
              balanceAfter: _int(data['balance_after']),
              reason: _string(data['reason']),
              createdAt: _date(data['created_at'], now),
            );
          }).toList()
        : <PointTransaction>[];
    return PointsOverview(
      balance: _int(value['balance']),
      transactions: transactions,
    );
  }

  Future<List<StoreOrder>> orders() async {
    final value = await _client.getJson('/api/v1/me/store-orders');
    final raw = value['items'];
    if (raw is! List) return const <StoreOrder>[];
    return raw.whereType<Map>().map((item) {
      final data = Map<String, dynamic>.from(item);
      return _orderFromJson(data);
    }).toList();
  }

  Future<StoreOrder> order(String id) async {
    final value = await _client.getJson('/api/v1/me/store-orders/$id');
    return _orderFromJson(value);
  }

  Future<StoreOrder> submitShipping({
    required String orderId,
    required String recipientName,
    required String phone,
    required String province,
    required String city,
    required String district,
    required String addressDetail,
  }) async {
    final value = await _client.putJson(
      '/api/v1/me/store-orders/$orderId/shipping',
      body: {
        'recipient_name': recipientName,
        'phone': phone,
        'province': province,
        'city': city,
        'district': district,
        'address_detail': addressDetail,
      },
    );
    return _orderFromJson(value);
  }

  Future<Map<String, dynamic>> redeem(
    String productId, {
    required String idempotencyKey,
  }) => _client.postJson(
    '/api/v1/store/orders',
    body: {'product_id': productId},
    headers: {'Idempotency-Key': idempotencyKey},
  );

  String _string(dynamic value, {String fallback = ''}) =>
      value is String ? value : fallback;
  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  DateTime _date(dynamic value, DateTime fallback) =>
      value is String ? DateTime.tryParse(value) ?? fallback : fallback;
  DateTime? _nullableDate(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  StoreOrder _orderFromJson(Map<String, dynamic> data) => StoreOrder(
    id: _string(data['id']),
    productId: _string(data['product_id']),
    productName: _string(data['product_name']),
    points: _int(data['points']),
    status: _string(data['status']),
    fulfillmentStatus: _string(data['fulfillment_status'], fallback: 'none'),
    createdAt: _date(data['created_at'], DateTime.now().toUtc()),
    reviewReason: _string(data['review_reason']),
    reviewedAt: _nullableDate(data['reviewed_at']),
    shippedAt: _nullableDate(data['shipped_at']),
    completedAt: _nullableDate(data['completed_at']),
    shipping: _shippingFromJson(data['shipping']),
  );

  StoreOrderShipping? _shippingFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final data = Map<String, dynamic>.from(raw);
    return StoreOrderShipping(
      recipientName: _string(data['recipient_name']),
      phone: _string(data['phone']),
      province: _string(data['province']),
      city: _string(data['city']),
      district: _string(data['district']),
      addressDetail: _string(data['address_detail']),
      carrier: _string(data['carrier']),
      trackingNo: _string(data['tracking_no']),
      maskedName: _string(data['masked_name']),
      maskedPhone: _string(data['masked_phone']),
      maskedAddress: _string(data['masked_address']),
      submittedAt: _nullableDate(data['submitted_at']),
      updatedAt: _nullableDate(data['updated_at']),
    );
  }
}
