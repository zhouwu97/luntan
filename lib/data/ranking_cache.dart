import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../screens/ranking_page.dart';

/// 排行榜缓存的最小抽象，便于页面测试使用内存实现。
abstract interface class RankingCacheStore {
  Future<RankingCacheSnapshot?> read();

  Future<void> write(List<RankingItem> items, {required DateTime updatedAt});
}

class RankingCacheSnapshot {
  const RankingCacheSnapshot({required this.items, required this.updatedAt});

  final List<RankingItem> items;
  final DateTime updatedAt;
}

/// 只缓存最近一次服务端成功返回的完整榜单，不缓存静态演示数据。
class RankingCache implements RankingCacheStore {
  RankingCache(this._preferences, {this.storageKey = defaultStorageKey});

  static const defaultStorageKey = 'luntan.ranking.real-cache.v1';

  final SharedPreferences _preferences;
  final String storageKey;

  static Future<RankingCache> create({String? namespace}) async {
    final key = namespace == null || namespace.trim().isEmpty
        ? defaultStorageKey
        : '$defaultStorageKey.${_safeNamespace(namespace)}';
    return RankingCache(await SharedPreferences.getInstance(), storageKey: key);
  }

  static String _safeNamespace(String value) => base64Url
      .encode(utf8.encode(value))
      .replaceAll('=', '')
      .replaceAll('-', '_');

  @override
  Future<RankingCacheSnapshot?> read() async {
    final raw = _preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final updatedAt = DateTime.tryParse('${decoded['updated_at'] ?? ''}');
      final rawItems = decoded['items'];
      if (updatedAt == null || rawItems is! List) return null;
      final items = rawItems
          .whereType<Map>()
          .map((item) => RankingItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      if (items.isEmpty) return null;
      return RankingCacheSnapshot(items: items, updatedAt: updatedAt);
    } on FormatException {
      await _preferences.remove(storageKey);
      return null;
    }
  }

  @override
  Future<void> write(
    List<RankingItem> items, {
    required DateTime updatedAt,
  }) async {
    if (items.isEmpty) return;
    await _preferences.setString(
      storageKey,
      jsonEncode({
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
      }),
    );
  }
}

/// 测试和无持久化场景使用的缓存实现。
class MemoryRankingCache implements RankingCacheStore {
  RankingCacheSnapshot? snapshot;

  @override
  Future<RankingCacheSnapshot?> read() async => snapshot;

  @override
  Future<void> write(
    List<RankingItem> items, {
    required DateTime updatedAt,
  }) async {
    snapshot = RankingCacheSnapshot(
      items: List.unmodifiable(items),
      updatedAt: updatedAt,
    );
  }
}
