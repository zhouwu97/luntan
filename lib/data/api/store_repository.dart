import 'api_client.dart';

class ApiStoreProduct {
  const ApiStoreProduct({required this.id, required this.name, required this.description, required this.emoji, required this.points, required this.color});
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
      return ApiStoreProduct(id: _string(data['id']), name: _string(data['name']), description: _string(data['description']), emoji: _string(data['emoji']), points: _int(data['points']), color: _int(data['color']));
    }).toList();
  }

  Future<int> balance() async {
    final value = await _client.getJson('/api/v1/me/points');
    return _int(value['balance']);
  }

  Future<Map<String, dynamic>> redeem(String productId) => _client.postJson('/api/v1/store/orders', body: {'product_id': productId});

  String _string(dynamic value) => value is String ? value : '';
  int _int(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
