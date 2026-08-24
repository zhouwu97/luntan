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
  });
  final String id;
  final String name;
  final String description;
  final String emoji;
  final int points;
  final int color;
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

  Future<Map<String, dynamic>> redeem(
    String productId, {
    required String idempotencyKey,
  }) => _client.postJson(
    '/api/v1/store/orders',
    body: {'product_id': productId},
    headers: {'Idempotency-Key': idempotencyKey},
  );

  String _string(dynamic value) => value is String ? value : '';
  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  DateTime _date(dynamic value, DateTime fallback) =>
      value is String ? DateTime.tryParse(value) ?? fallback : fallback;
}
