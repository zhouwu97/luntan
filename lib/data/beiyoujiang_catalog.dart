import 'dart:convert';

import 'package:flutter/services.dart';

/// 杯友酱公开榜单的离线镜像。
///
/// 快照由 scripts/sync_beiyoujiang_rankings.ps1 生成。每一个视图都保存
/// 源站返回的顺序，客户端只读取，不再二次按评分或热度排序。
class BeiyoujiangCatalog {
  const BeiyoujiangCatalog({
    required this.fetchedAt,
    required Map<String, BeiyoujiangRankingView> views,
  }) : _views = views;

  final DateTime? fetchedAt;
  final Map<String, BeiyoujiangRankingView> _views;

  static Future<BeiyoujiangCatalog> load() async {
    final raw = await rootBundle.loadString(
      'assets/ranking/beiyoujiang_snapshot.json',
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('杯友酱榜单快照格式错误');
    }
    final data = Map<String, dynamic>.from(decoded);
    final rawViews = data['views'];
    if (rawViews is! Map) {
      throw const FormatException('杯友酱榜单快照缺少视图数据');
    }
    final views = <String, BeiyoujiangRankingView>{};
    for (final entry in rawViews.entries) {
      if (entry.value is Map) {
        views['${entry.key}'] = BeiyoujiangRankingView.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }
    return BeiyoujiangCatalog(
      fetchedAt: DateTime.tryParse('${data['fetched_at'] ?? ''}'),
      views: views,
    );
  }

  BeiyoujiangRankingView viewFor({
    required String tab,
    required String category,
  }) {
    final requested = _views['$tab|$category'];
    if (requested != null) return requested;

    // 源站切换训练标签时，默认自动展示“飞机杯”分类。
    if (tab.isNotEmpty) {
      final cup = _views['$tab|CUP'];
      if (cup != null) return cup;
    }
    return _views['|'] ?? const BeiyoujiangRankingView.empty();
  }

  List<BeiyoujiangCatalogItem> get searchableItems {
    final itemsById = <String, BeiyoujiangCatalogItem>{};
    for (final view in _views.values) {
      for (final item in [view.weeklyTop, ...view.items]) {
        if (item != null) itemsById.putIfAbsent(item.id, () => item);
      }
    }
    final items = itemsById.values.toList();
    items.sort((left, right) => left.name.compareTo(right.name));
    return items;
  }
}

class BeiyoujiangRankingView {
  const BeiyoujiangRankingView({required this.weeklyTop, required this.items});

  const BeiyoujiangRankingView.empty() : weeklyTop = null, items = const [];

  final BeiyoujiangCatalogItem? weeklyTop;
  final List<BeiyoujiangCatalogItem> items;

  factory BeiyoujiangRankingView.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return BeiyoujiangRankingView(
      weeklyTop: json['weekly_top'] is Map
          ? BeiyoujiangCatalogItem.fromJson(
              Map<String, dynamic>.from(json['weekly_top'] as Map),
            )
          : null,
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => BeiyoujiangCatalogItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class BeiyoujiangCatalogItem {
  const BeiyoujiangCatalogItem({
    required this.id,
    required this.rank,
    required this.name,
    required this.merchant,
    required this.releaseYear,
    required this.description,
    required this.tags,
    required this.coverKey,
    required this.wantCount,
    required this.wantCountText,
    required this.reviewCount,
    required this.score,
    required this.category,
    required this.stimulation,
    this.shopLink,
    this.heroKey,
  });

  final String id;
  final int rank;
  final String name;
  final String merchant;
  final int releaseYear;
  final String description;
  final List<String> tags;
  final String coverKey;
  final String? heroKey;
  final int wantCount;
  final String wantCountText;
  final int reviewCount;
  final double score;
  final String category;
  final String stimulation;
  final String? shopLink;

  factory BeiyoujiangCatalogItem.fromJson(Map<String, dynamic> json) {
    List<String> imageKeys(dynamic value) => value is List
        ? value.map((item) => '$item').where((item) => item.isNotEmpty).toList()
        : const [];
    final covers = imageKeys(json['coverUrl']);
    final heroImages = imageKeys(json['weeklyTopImg']);
    final tagsValue = '${json['tags'] ?? ''}';
    return BeiyoujiangCatalogItem(
      id: '${json['id'] ?? ''}',
      rank: _int(json['rank']),
      name: '${json['name'] ?? ''}',
      merchant: '${json['merchant'] ?? ''}',
      releaseYear: _int(json['releaseYear']),
      description: '${json['description'] ?? ''}',
      tags: tagsValue.isEmpty
          ? const []
          : tagsValue.split(',').where((tag) => tag.isNotEmpty).toList(),
      coverKey: covers.isEmpty ? '' : covers.first,
      heroKey: heroImages.isEmpty ? null : heroImages.first,
      wantCount: _int(json['wantCount']),
      wantCountText:
          '${json['wantCountStr'] ?? '${_int(json['wantCount'])}人想冲'}',
      reviewCount: _int(json['reviewCount']),
      score: _double(json['rating']),
      category: '${json['category'] ?? ''}',
      stimulation: '${json['stimulation'] ?? ''}',
      shopLink: _nullableString(json['shopLink']),
    );
  }

  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static double _double(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static String? _nullableString(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  String imageUrlFor({bool hero = false}) {
    final key = hero ? (heroKey ?? coverKey) : coverKey;
    if (key.isEmpty) return '';
    return Uri.https('beiyoujiang.com', '/ToyImg/$key').toString();
  }

  String get detailUrl => Uri.https('beiyoujiang.com', '/bang/$id').toString();
}
