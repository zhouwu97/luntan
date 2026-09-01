import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../data/api/publish_repository.dart';
import '../data/api/ranking_repository.dart';
import '../data/app_links.dart';
import '../data/ranking_cache.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/app_network_image.dart';
import '../widgets/comments/ranking_comment_thread_sheet.dart';
import '../widgets/comments/comment_more_button.dart';
import '../widgets/comments/comment_image_viewer.dart';
import '../widgets/comments/comment_skeleton.dart';
import 'ranking_reorder_screen.dart';
import 'ranking_toy_submission_screen.dart';

/// `rankingList` 网页上的一条玩具排行数据。
class RankingItem {
  const RankingItem({
    required this.rank,
    required this.name,
    required this.hot,
    required this.tags,
    required this.ratings,
    required this.score,
    required this.asset,
    this.id = '',
    this.merchant = 'TMT',
    this.releaseYear = 2026,
    this.description = '',
    this.category = 'cup',
    this.segments = const [],
    this.ratingDistribution = const {},
    this.remoteImageUrl,
    this.couponUrl,
    this.sourceUrl,
  });

  final int rank;
  final String name;
  final String hot;
  final List<String> tags;
  final String ratings;
  final String score;
  final String asset;
  final String id;
  final String merchant;
  final int releaseYear;
  final String description;
  final String category;
  final List<String> segments;
  final Map<int, int> ratingDistribution;
  final String? remoteImageUrl;
  final String? couponUrl;
  final String? sourceUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'rank': rank,
    'name': name,
    'hot': hot,
    'tags': tags,
    'ratings': ratings,
    'score': score,
    'asset': asset,
    'merchant': merchant,
    'release_year': releaseYear,
    'description': description,
    'category': category,
    'segments': segments,
    'remote_image_url': remoteImageUrl,
    'coupon_url': couponUrl,
    'source_url': sourceUrl,
    'rating_distribution': ratingDistribution.map(
      (key, value) => MapEntry('$key', value),
    ),
  };

  factory RankingItem.fromJson(Map<String, dynamic> json) {
    final rawDistribution = json['rating_distribution'];
    final distribution = <int, int>{};
    if (rawDistribution is Map) {
      for (final entry in rawDistribution.entries) {
        final key = int.tryParse('${entry.key}');
        final value = entry.value is num
            ? (entry.value as num).toInt()
            : int.tryParse('${entry.value}');
        if (key != null && value != null) distribution[key] = value;
      }
    }
    List<String> strings(dynamic value) =>
        value is List ? value.whereType<String>().toList() : const <String>[];
    return RankingItem(
      id: '${json['id'] ?? ''}',
      rank: json['rank'] is num ? (json['rank'] as num).toInt() : 0,
      name: '${json['name'] ?? ''}',
      hot: '${json['hot'] ?? ''}',
      tags: strings(json['tags']),
      ratings: '${json['ratings'] ?? ''}',
      score: '${json['score'] ?? ''}',
      asset: '${json['asset'] ?? ''}',
      merchant: '${json['merchant'] ?? 'TMT'}',
      releaseYear: json['release_year'] is num
          ? (json['release_year'] as num).toInt()
          : 2026,
      description: '${json['description'] ?? ''}',
      category: '${json['category'] ?? 'cup'}',
      segments: strings(json['segments']),
      ratingDistribution: distribution,
      remoteImageUrl: json['remote_image_url'] as String?,
      couponUrl: json['coupon_url'] as String?,
      sourceUrl: json['source_url'] as String?,
    );
  }
}

/// 源站的“想冲”人数文案：千位以上缩写为 k，与源站展示一致。
String rankingWantCountText(int count) {
  if (count < 1000) return '$count人想冲';
  final k = count / 1000;
  final text = k == k.roundToDouble()
      ? k.toStringAsFixed(0)
      : k.toStringAsFixed(1);
  return '${text}k人想冲';
}

/// 判断接口错误是否为未登录（401），用于写操作失败后引导登录。
bool _isUnauthorized(Object error) =>
    error is ApiException && error.statusCode == 401;

/// 401/403 统一视为“当前身份不能写服务器”，想冲/买过回退本机标记。
bool _isAuthOrCapabilityDenied(Object error) =>
    error is ApiException &&
    (error.statusCode == 401 || error.statusCode == 403);

Widget _rankingImage(
  RankingItem item, {
  required double width,
  required double height,
  required BoxFit fit,
}) {
  final remoteUrl = item.remoteImageUrl;
  if (remoteUrl != null && remoteUrl.isNotEmpty) {
    return AppNetworkImage(
      url: remoteUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_) => _rankingImageFallback(item, width, height, fit),
    );
  }
  return _rankingImageFallback(item, width, height, fit);
}

Widget _rankingImageFallback(
  RankingItem item,
  double width,
  double height,
  BoxFit fit,
) {
  if (item.asset.isEmpty) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFEFF2F7),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        size: 20,
        color: Color(0xFFB7C2D4),
      ),
    );
  }
  return Image.asset(item.asset, width: width, height: height, fit: fit);
}

const _mainRankingItems = <RankingItem>[
  RankingItem(
    id: 'toy-yingchuan-2',
    rank: 2,
    name: '樱川爱 二代',
    hot: '401人想冲',
    tags: ['细密颗粒', '肉褶延续', '极致慢玩'],
    ratings: '17人评分',
    score: '9.9',
    asset: 'assets/ranking/thumb_02.webp',
    merchant: 'TMT',
    releaseYear: 2026,
    category: 'cup',
    segments: ['beginner'],
    description:
        '樱2软版本基本延续了前作的慢玩设定。设计结构网状结构+细密绒粒,完全属于纯新手属性的舒适按摩区，末尾方块状奇袭冲刺区也几乎拒绝一切强硬度挑战。相比琉璃子,此作才更能定义A酱最适合新手的杯子！',
  ),
  RankingItem(
    id: 'toy-yutou',
    rank: 3,
    name: '鱼头',
    hot: '497人想冲',
    tags: ['猎奇', '高性价比', '传说神器'],
    ratings: '90人评分',
    score: '9.1',
    asset: 'assets/ranking/thumb_03.webp',
    category: 'cup',
    segments: ['advanced'],
  ),
  RankingItem(
    id: 'toy-yuanqi',
    rank: 4,
    name: '元气教练',
    hot: '284人想冲',
    tags: ['强烈挤压', '脂软工艺', '后入抓握'],
    ratings: '6人评分',
    score: '9.3',
    asset: 'assets/ranking/thumb_04.webp',
    category: 'cup',
    segments: ['advanced'],
  ),
  RankingItem(
    id: 'toy-shendai',
    rank: 5,
    name: '神代雪乃',
    hot: '148人想冲',
    tags: ['顶级材料', '一字开腿', '冷门神作'],
    ratings: '11人评分',
    score: '9.8',
    asset: 'assets/ranking/thumb_05.jpg',
    category: 'half_body',
    segments: ['beginner', 'advanced'],
  ),
  RankingItem(
    id: 'toy-hoshino-2',
    rank: 6,
    name: '星野爱丽丝 二代',
    hot: '91人想冲',
    tags: ['慢玩大臀', '定制周边', '收藏属性'],
    ratings: '4人评分',
    score: '10',
    asset: 'assets/ranking/thumb_06.webp',
    category: 'large_hip',
    segments: ['beginner'],
  ),
  RankingItem(
    id: 'toy-nanako-2',
    rank: 7,
    name: '奈奈子 二代',
    hot: '430人想冲',
    tags: ['重装包裹', '柔厚肉壁', '渐进式'],
    ratings: '16人评分',
    score: '9.9',
    asset: 'assets/ranking/thumb_07.webp',
    category: 'cup',
    segments: ['advanced'],
  ),
  RankingItem(
    id: 'toy-aili',
    rank: 8,
    name: '双穴爱莉',
    hot: '365人想冲',
    tags: ['双穴包裹', '仿真慢玩', '舒适探索'],
    ratings: '14人评分',
    score: '9.1',
    asset: 'assets/ranking/thumb_08.webp',
    category: 'cup',
    segments: ['beginner'],
  ),
  RankingItem(
    id: 'toy-liulizi',
    rank: 9,
    name: '水着琉璃子',
    hot: '241人想冲',
    tags: ['A酱首选', '极易入门', '软呼呼'],
    ratings: '15人评分',
    score: '8.5',
    asset: 'assets/ranking/thumb_09.webp',
    category: 'cup',
    segments: ['beginner'],
  ),
  RankingItem(
    id: 'toy-kekelang',
    rank: 10,
    name: '可可狼姬',
    hot: '464人想冲',
    tags: ['黑皮', '榨汁强刮', '兽耳女仆'],
    ratings: '42人评分',
    score: '9',
    asset: 'assets/ranking/thumb_10.webp',
    category: 'cup',
    segments: ['juice', 'high_stim'],
  ),
  RankingItem(
    id: 'toy-piaogui-2',
    rank: 11,
    name: '皮小鬼 二代',
    hot: '301人想冲',
    tags: ['真实回弹', '肉感', '毕业臀模'],
    ratings: '33人评分',
    score: '7.9',
    asset: 'assets/ranking/thumb_11.webp',
    category: 'small_hip',
    segments: ['advanced'],
  ),
  RankingItem(
    id: 'toy-hu-hu-zi',
    rank: 12,
    name: '狐狐子',
    hot: '281人想冲',
    tags: ['一字马', '松鼠娘', '内部铆钉'],
    ratings: '15人评分',
    score: '9.7',
    asset: 'assets/ranking/thumb_12.png',
    category: 'small_hip',
    segments: ['high_stim'],
  ),
  RankingItem(
    id: 'toy-huanru',
    rank: 13,
    name: '幻乳龙娘',
    hot: '186人想冲',
    tags: ['巨乳巨臀', '重型泰坦', '阻塞黏腻'],
    ratings: '11人评分',
    score: '9.4',
    asset: 'assets/ranking/thumb_13.webp',
    category: 'large_hip',
    segments: ['high_stim', 'juice'],
  ),
  RankingItem(
    id: 'toy-xiaogui',
    rank: 14,
    name: '小鬼魔皇',
    hot: '297人想冲',
    tags: ['高刺榨汁', '重型机甲', '水波肉臀'],
    ratings: '23人评分',
    score: '9',
    asset: 'assets/ranking/thumb_14.webp',
    category: 'large_hip',
    segments: ['high_stim', 'juice'],
  ),
  RankingItem(
    id: 'toy-chiyuan',
    rank: 15,
    name: '赤鸢',
    hot: '36人想冲',
    tags: ['爆乳脂软', '大臀', '机械横纹'],
    ratings: '5人评分',
    score: '9.2',
    asset: 'assets/ranking/thumb_15.webp',
    category: 'large_hip',
    segments: ['high_stim'],
  ),
  RankingItem(
    id: 'toy-tun-niang',
    rank: 16,
    name: '五宫豚娘物语',
    hot: '145人想冲',
    tags: ['猎奇狂', '福瑞控', '海豚仿生'],
    ratings: '11人评分',
    score: '7.9',
    asset: 'assets/ranking/thumb_16.webp',
    category: 'cup',
    segments: ['high_stim'],
  ),
  RankingItem(
    id: 'toy-baishi-2',
    rank: 17,
    name: '白丝壁女 二代',
    hot: '91人想冲',
    tags: ['重力负压', '暴力内腔', '加硬'],
    ratings: '7人评分',
    score: '5.9',
    asset: 'assets/ranking/thumb_17.webp',
    category: 'half_body',
    segments: ['high_stim'],
  ),
  RankingItem(
    id: 'toy-gonglai',
    rank: 18,
    name: '宫濑 Soft',
    hot: '426人想冲',
    tags: ['脂软材质', '细密包裹', '超软慢玩'],
    ratings: '26人评分',
    score: '8.7',
    asset: 'assets/ranking/thumb_18.webp',
    category: 'cup',
    segments: ['beginner'],
  ),
  RankingItem(
    id: 'toy-qianmei',
    rank: 19,
    name: '千美',
    hot: '61人想冲',
    tags: ['直筒型', '极致肉厚', '被动包裹'],
    ratings: '5人评分',
    score: '9',
    asset: 'assets/ranking/thumb_19.webp',
    category: 'cup',
    segments: ['advanced'],
  ),
  RankingItem(
    id: 'toy-shuiye-2',
    rank: 20,
    name: '水野 2',
    hot: '429人想冲',
    tags: ['体脂水感', '温和型', '顺滑贴合'],
    ratings: '5人评分',
    score: '9.1',
    asset: 'assets/ranking/thumb_20.webp',
    category: 'lubricant',
    segments: ['beginner'],
  ),
];

const _topRankingItem = RankingItem(
  id: 'toy-butter-2',
  rank: 1,
  name: '黄油小姐 二代',
  hot: '401人想冲',
  tags: ['奶香体质', '软糯入门', '果冻包裹'],
  ratings: '17人评分',
  score: '8.7',
  asset: 'assets/ranking/hero.webp',
  merchant: 'COC',
  releaseYear: 2025,
  category: 'cup',
  segments: ['beginner'],
  ratingDistribution: {8: 5, 9: 12},
  description: '相较前作，黄油小姐2完成了一次华丽的材质蜕变。奶香味提升，肉质的软糯度提升极佳。大结构轨道带来的异物包裹感实战体验飙升。',
);

const _rankingTabs = ['综合热榜', '慢玩入门', '进阶训练', '超高刺激', '榨汁玩具'];

class RankingPage extends StatefulWidget {
  const RankingPage({
    super.key,
    this.repository,
    this.platformRepository,
    this.publishRepository,
    this.isAuthenticated = false,
    this.canComment = false,
    this.canLike = false,
    this.canVote = false,
    this.canManageRanking = false,
    this.onRequireAuth,
    this.cache,
  });

  final RankingRepository? repository;
  final PlatformRepository? platformRepository;
  final PublishRepository? publishRepository;
  final bool isAuthenticated;
  final bool canComment;
  final bool canLike;
  final bool canVote;
  final bool canManageRanking;
  final VoidCallback? onRequireAuth;
  final RankingCacheStore? cache;

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedTab = 0;
  int _selectedCategory = -1;
  List<RankingItem>? _remoteItems;
  RankingItem? _weeklyTopItem;
  List<RankingItem>? _allRemoteItems;
  DateTime? _remoteUpdatedAt;
  Object? _remoteError;
  bool _loadingRemote = false;

  static const _sourceTabKeys = ['', 'ENTRY', 'ADVANCED', 'HIGH', 'EXTREME'];
  static const _sourceCategoryKeys = [
    'CUP',
    'SMALL_MOLD',
    'LARGE_MOLD',
    'HALF_BODY',
    'LUBE',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.repository != null) {
      _loadRemoteRanking();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _selectedTabKey => _sourceTabKeys[_selectedTab];

  String? get _selectedCategoryKey =>
      _selectedCategory < 0 ? null : _sourceCategoryKeys[_selectedCategory];

  Future<void> _loadRemoteRanking() async {
    if (_loadingRemote) return;
    _loadingRemote = true;
    final isDefaultView =
        _selectedTabKey.isEmpty && _selectedCategoryKey == null;
    final cache = widget.cache ?? await RankingCache.create();
    if (isDefaultView) {
      final cached = await cache.read();
      if (mounted && cached != null) {
        setState(() {
          _remoteItems = cached.items;
          _remoteUpdatedAt = cached.updatedAt;
        });
      }
    }
    try {
      final list = await widget.repository!.list(
        tab: _selectedTabKey.isEmpty ? null : _selectedTabKey,
        category: _selectedCategoryKey,
      );
      final items = list.items.map(_itemFromRemote).toList();
      if (isDefaultView && items.isNotEmpty) {
        await cache.write(items, updatedAt: DateTime.now().toUtc());
      }
      if (!mounted) return;
      setState(() {
        _remoteItems = items;
        _weeklyTopItem = list.weeklyTop == null
            ? null
            : _itemFromRemote(list.weeklyTop!, useHero: true);
        _remoteUpdatedAt = DateTime.now().toUtc();
        _remoteError = null;
        _allRemoteItems = isDefaultView ? items : _allRemoteItems;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _remoteError = error);
      }
    } finally {
      _loadingRemote = false;
    }
    // 全量条目用于站内搜索；失败时只影响搜索结果。
    if (_allRemoteItems == null) {
      try {
        final all = await widget.repository!.list();
        if (!mounted) return;
        setState(() {
          _allRemoteItems = all.items.map(_itemFromRemote).toList();
        });
      } catch (_) {
        // 搜索数据缺失时保留当前视图数据。
      }
    }
  }

  /// 源站的“想冲”人数文案：千位以上缩写为 k，与源站展示一致。
  RankingItem _itemFromRemote(RankingToy toy, {bool useHero = false}) {
    final score = toy.score == toy.score.roundToDouble()
        ? toy.score.toStringAsFixed(0)
        : toy.score.toStringAsFixed(1);
    final remoteUrl = useHero ? (toy.heroUrl ?? toy.coverUrl) : toy.coverUrl;
    return RankingItem(
      id: toy.id,
      rank: toy.rank,
      name: toy.name,
      hot: rankingWantCountText(toy.wantCount),
      tags: toy.tags,
      ratings: '${toy.ratingCount}人评分',
      score: score,
      asset: '',
      merchant: toy.merchant,
      releaseYear: toy.releaseYear,
      description: toy.description,
      category: toy.category,
      segments: toy.segments,
      remoteImageUrl: remoteUrl,
      couponUrl: toy.couponUrl,
      sourceUrl: toy.sourceUrl,
    );
  }

  List<RankingItem> get _allSourceItems {
    if (widget.repository != null) {
      return _allRemoteItems ?? _remoteItems ?? const [];
    }
    return [_topRankingItem, ..._mainRankingItems];
  }

  List<RankingItem> get _filteredItems {
    final query = _searchQuery.trim().toLowerCase();
    if (widget.repository != null) {
      final source = query.isEmpty
          ? (_remoteItems ?? const <RankingItem>[])
          : _allSourceItems;
      if (query.isEmpty) return source;
      return source.where((item) {
        final matchesName = item.name.toLowerCase().contains(query);
        final matchesMerchant = item.merchant.toLowerCase().contains(query);
        final matchesDesc = item.description.toLowerCase().contains(query);
        final matchesTags = item.tags.any(
          (t) => t.toLowerCase().contains(query),
        );
        return matchesName || matchesMerchant || matchesDesc || matchesTags;
      }).toList();
    }
    return _allSourceItems.where((item) {
      if (query.isNotEmpty) {
        final matchesName = item.name.toLowerCase().contains(query);
        final matchesMerchant = item.merchant.toLowerCase().contains(query);
        final matchesDesc = item.description.toLowerCase().contains(query);
        final matchesTags = item.tags.any(
          (t) => t.toLowerCase().contains(query),
        );
        if (!matchesName && !matchesMerchant && !matchesDesc && !matchesTags) {
          return false;
        }
        return true;
      }

      // 1. Tab filter (segments)
      if (_selectedTab == 1 && !item.segments.contains('beginner')) {
        return false;
      }
      if (_selectedTab == 2 && !item.segments.contains('advanced')) {
        return false;
      }
      if (_selectedTab == 3 && !item.segments.contains('high_stim')) {
        return false;
      }
      if (_selectedTab == 4 && !item.segments.contains('juice')) {
        return false;
      }

      // 2. Category filter
      final catKey = switch (_selectedCategory) {
        0 => 'cup',
        1 => 'small_hip',
        2 => 'large_hip',
        3 => 'half_body',
        4 => 'lubricant',
        _ => '',
      };
      if (catKey.isNotEmpty && item.category != catKey) return false;

      return true;
    }).toList();
  }

  RankingItem get _topItem {
    if (widget.repository != null) {
      if (_searchQuery.trim().isEmpty && _weeklyTopItem != null) {
        return _weeklyTopItem!;
      }
      final items = _filteredItems;
      if (items.isEmpty) return _topRankingItem;
      return items.firstWhere(
        (item) => item.rank == 1,
        orElse: () => items.first,
      );
    }
    final items = _filteredItems;
    if (items.isEmpty) return _topRankingItem;
    return items.firstWhere(
      (item) => item.rank == 1,
      orElse: () => items.first,
    );
  }

  void _openRankingItem(RankingItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RankingItemDetailPage(
          item: item,
          repository: widget.repository,
          isAuthenticated: widget.isAuthenticated,
          canComment: widget.canComment,
          canLike: widget.canLike,
          canVote: widget.canVote,
          canManageRanking: widget.canManageRanking,
          onRequireAuth: widget.onRequireAuth,
        ),
      ),
    );
  }

  void _openSubmissionForm() {
    if (!widget.isAuthenticated) {
      widget.onRequireAuth?.call();
      return;
    }
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => RankingToySubmissionScreen(
              rankingRepository: widget.repository!,
              publishRepository: widget.publishRepository!,
            ),
          ),
        )
        .then((submitted) {
          if (submitted == true) {
            _loadRemoteRanking();
          }
        });
  }

  void _openReorderScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RankingReorderScreen(
          rankingRepository: widget.repository!,
          platformRepository: widget.platformRepository!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF2F1F6),
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          _RankingHeader(
            onBack: () => Navigator.of(context).maybePop(),
            searchController: _searchController,
            onSearchChanged: (value) => setState(() => _searchQuery = value),
            onClearSearch: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
            actions: [
              if (widget.repository != null && widget.publishRepository != null)
                Tooltip(
                  message: '投稿新玩具',
                  child: IconButton(
                    onPressed: _openSubmissionForm,
                    icon: const Icon(
                      Icons.add_circle_outline,
                      size: 24,
                      color: Color(0xFFF25B91),
                    ),
                  ),
                ),
              if (widget.canManageRanking &&
                  widget.repository != null &&
                  widget.platformRepository != null)
                Tooltip(
                  message: '调整榜单名次',
                  child: IconButton(
                    onPressed: _openReorderScreen,
                    icon: const Icon(
                      Icons.swap_vert,
                      size: 22,
                      color: Color(0xFF263238),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(child: _rankingScrollView()),
        ],
      ),
    ),
  );

  Widget _rankingScrollView() {
    if (widget.repository != null &&
        _remoteError != null &&
        _remoteItems == null) {
      return _RankingLoadError(onRetry: _loadRemoteRanking);
    }
    if (widget.repository != null && _remoteItems == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final query = _searchQuery.trim();
    final items = _filteredItems;

    if (query.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: 1 + (items.isEmpty ? 1 : items.length),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 4),
              child: Text(
                '找到 ${items.length} 个榜单结果',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  '未找到匹配的榜单商品',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                ),
              ),
            );
          }
          final item = items[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RankingCard(
              item: item,
              onTap: () => _openRankingItem(item),
            ),
          );
        },
      );
    }

    final showTopBanner =
        (_searchQuery.trim().isEmpty && _weeklyTopItem != null) ||
        (_selectedTab == 0 && items.any((i) => i.rank == 1));
    final listItems = showTopBanner
        ? items.where((i) => i.id != _topItem.id).toList()
        : items;

    final headers = <Widget>[
      if (widget.repository != null &&
          _remoteError != null &&
          _remoteItems != null)
        _RankingStaleBanner(
          updatedAt: _remoteUpdatedAt,
          onRetry: _loadRemoteRanking,
        ),
      _RankingTabs(
        selectedIndex: _selectedTab,
        onTap: (index) {
          setState(() {
            _selectedTab = index;
            if (index > 0 && _selectedCategory < 0) {
              _selectedCategory = 0;
            }
          });
          if (widget.repository != null) _loadRemoteRanking();
        },
      ),
      _CategoryGrid(
        selectedIndex: _selectedCategory,
        onTap: (index) {
          setState(() {
            if (_selectedTab == 0 && index == _selectedCategory) {
              _selectedCategory = -1;
            } else {
              _selectedCategory = index;
            }
          });
          if (widget.repository != null) _loadRemoteRanking();
        },
      ),
      if (showTopBanner)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _TopRankingCard(
                item: _topItem,
                onTap: () => _openRankingItem(_topItem),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      if (listItems.isEmpty && !showTopBanner)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              '该分类暂无商品',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
          ),
        ),
    ];

    return ListView.builder(
      itemCount: headers.length + listItems.length,
      itemBuilder: (context, index) {
        if (index < headers.length) return headers[index];
        final item = listItems[index - headers.length];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _RankingCard(item: item, onTap: () => _openRankingItem(item)),
        );
      },
    );
  }
}

class _RankingLoadError extends StatelessWidget {
  const _RankingLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('排行榜暂时无法加载', style: TextStyle(color: Color(0xFF6B7280))),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

class _RankingStaleBanner extends StatelessWidget {
  const _RankingStaleBanner({required this.updatedAt, required this.onRetry});

  final DateTime? updatedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final time = updatedAt == null
        ? ''
        : '（${updatedAt!.toLocal().month}月${updatedAt!.toLocal().day}日更新）';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 17,
            color: Color(0xFFB7791F),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '数据更新失败，当前展示缓存$time',
              style: const TextStyle(color: Color(0xFF8A5A13), fontSize: 12),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _RankingHeader extends StatelessWidget {
  const _RankingHeader({
    required this.onBack,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    this.actions = const <Widget>[],
  });

  final VoidCallback onBack;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Tooltip(
            message: '返回',
            child: IconButton(
              onPressed: onBack,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 38),
              icon: const Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: Color(0xFF263238),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  hintText: '搜索：魅魔、大魔王、慢玩...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: Color(0xFF9CA3AF),
                  ),
                  prefixIconConstraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 38,
                  ),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          icon: const Icon(
                            Icons.clear_rounded,
                            color: Color(0xFF9CA3AF),
                          ),
                          onPressed: onClearSearch,
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 38,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          ...actions,
        ],
      ),
    ),
  );
}

class _RankingTabs extends StatelessWidget {
  const _RankingTabs({required this.selectedIndex, required this.onTap});

  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Container(
    height: 46,
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < _rankingTabs.length; index++) ...[
            _TabButton(
              label: _rankingTabs[index],
              selected: index == selectedIndex,
              onTap: () => onTap(index),
            ),
            if (index != _rankingTabs.length - 1) const SizedBox(width: 16),
          ],
        ],
      ),
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 46,
        child: Align(
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF333333)
                  : const Color(0xFF6B7280),
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    ),
  );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.selectedIndex, required this.onTap});

  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Container(
    height: 97,
    color: const Color(0xFFF9FAFB),
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        _CategoryButton(
          label: '飞机杯',
          icon: Icons.local_drink_outlined,
          selected: selectedIndex == 0,
          onTap: () => onTap(0),
        ),
        const SizedBox(width: 10),
        _CategoryButton(
          label: '小型臀模',
          icon: Icons.circle_outlined,
          selected: selectedIndex == 1,
          onTap: () => onTap(1),
        ),
        const SizedBox(width: 10),
        _CategoryButton(
          label: '大型臀模',
          asset: 'assets/ranking/category_large.png',
          selected: selectedIndex == 2,
          onTap: () => onTap(2),
        ),
        const SizedBox(width: 10),
        _CategoryButton(
          label: '半身腿模',
          asset: 'assets/ranking/category_legs.png',
          selected: selectedIndex == 3,
          onTap: () => onTap(3),
        ),
        const SizedBox(width: 10),
        _CategoryButton(
          label: '润滑油',
          icon: Icons.tune_rounded,
          selected: selectedIndex == 4,
          onTap: () => onTap(4),
        ),
      ],
    ),
  );
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.asset,
  });

  final String label;
  final IconData? icon;
  final String? asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 65,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF7FA) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFFF19ABB)
                  : const Color(0xFFEEF0F4),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x03000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (asset != null)
                Image.asset(asset!, width: 28, height: 28, fit: BoxFit.contain)
              else
                Icon(
                  icon,
                  size: 27,
                  color: selected
                      ? const Color(0xFFF25B91)
                      : const Color(0xFFBDBDBD),
                ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFF25B91)
                      : const Color(0xFF4B5563),
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TopRankingCard extends StatelessWidget {
  const _TopRankingCard({required this.item, required this.onTap});

  final RankingItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    onTap: onTap,
    label: '第1名 ${item.name}，${item.score} 分',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 214,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF3F4F6)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            SizedBox(
              height: 142,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _rankingImage(
                    item,
                    width: double.infinity,
                    height: 142,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF05D78),
                        borderRadius: BorderRadius.only(
                          bottomRight: Radius.circular(10),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(9, 5, 10, 5),
                        child: Text(
                          'NO.1 本周霸权',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF222222),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 4,
                            runSpacing: 3,
                            children: item.tags.map(_TagChip.new).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            item.score,
                            style: TextStyle(
                              color: Color(0xFFEA6D93),
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 2),
                          Text(
                            '分',
                            style: TextStyle(
                              color: Color(0xFFB7B7B7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 榜单商品详情页；布局对齐源站的商品介绍、评分和评价流。
class RankingItemDetailPage extends StatefulWidget {
  const RankingItemDetailPage({
    super.key,
    required this.item,
    this.repository,
    this.isAuthenticated = false,
    this.canComment = false,
    this.canLike = false,
    this.canVote = false,
    this.canManageRanking = false,
    this.onRequireAuth,
  });

  final RankingItem item;
  final RankingRepository? repository;
  final bool isAuthenticated;
  final bool canComment;
  final bool canLike;
  final bool canVote;
  final bool canManageRanking;
  final VoidCallback? onRequireAuth;

  @override
  State<RankingItemDetailPage> createState() => _RankingItemDetailPageState();
}

class _RankingItemDetailPageState extends State<RankingItemDetailPage> {
  static const _ink = Color(0xFF182C49);

  final _commentController = TextEditingController();
  bool _wanted = false;
  bool _owned = false;
  bool _wantedSaving = false;
  bool _ownedSaving = false;
  int _wantedRequestVersion = 0;
  int _ownedRequestVersion = 0;
  bool _sortByWeight = true;
  RankingToyDetail? _remoteDetail;
  bool _remoteLoading = false;
  String? _remoteError;
  bool _commentsLoadingMore = false;
  String? _commentsLoadMoreError;

  RankingItem get item => widget.item;

  RankingItem get displayItem {
    final toy = _remoteDetail?.toy;
    if (toy == null) return item;
    return RankingItem(
      id: toy.id,
      rank: toy.rank,
      name: toy.name,
      hot: rankingWantCountText(toy.wantCount),
      tags: toy.tags,
      ratings: '${toy.ratingCount}人评分',
      score: _scoreText(toy.score),
      asset: item.asset,
      merchant: toy.merchant,
      releaseYear: toy.releaseYear,
      description: toy.description,
      category: toy.category,
      segments: toy.segments,
      ratingDistribution:
          _remoteDetail?.ratingDistribution ?? item.ratingDistribution,
      remoteImageUrl: toy.coverUrl ?? toy.heroUrl ?? item.remoteImageUrl,
      couponUrl: toy.couponUrl ?? item.couponUrl,
      sourceUrl: toy.sourceUrl ?? item.sourceUrl,
    );
  }

  String get _description => _remoteDetail?.toy.description.isNotEmpty == true
      ? _remoteDetail!.toy.description
      : item.description.isNotEmpty
      ? item.description
      : '这款玩具延续了舒适慢玩的设计，适合在熟悉自己的节奏后逐步体验。';

  String get _wantCount =>
      _remoteDetail?.toy.wantCount.toString() ?? item.hot.replaceAll('人想冲', '');

  String get _reviewCount =>
      _remoteDetail?.toy.ratingCount.toString() ??
      item.ratings.replaceAll('人评分', '');

  String get _score =>
      _remoteDetail == null ? item.score : _scoreText(_remoteDetail!.toy.score);

  List<RankingToyComment>? get _serverComments => _remoteDetail?.comments;

  bool get _hasServer => widget.repository != null && item.id.trim().isNotEmpty;

  static String _scoreText(double score) => score == score.roundToDouble()
      ? score.toStringAsFixed(0)
      : score.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    if (_hasServer) _loadRemoteDetail();
  }

  Future<void> _loadRemoteDetail() async {
    final requestedSort = _sortByWeight;
    if (_remoteDetail == null) {
      setState(() {
        _remoteLoading = true;
        _remoteError = null;
      });
    }
    try {
      final detail = await widget.repository!.detail(
        item.id,
        commentSort: requestedSort ? 'weight' : 'latest',
      );
      if (!mounted) return;
      setState(() {
        _remoteDetail = detail;
        _sortByWeight = detail.commentSort != 'latest';
        _wanted = detail.toy.wanted;
        _owned = detail.toy.owned;
        _remoteLoading = false;
        _remoteError = null;
        _commentsLoadingMore = false;
        _commentsLoadMoreError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _remoteLoading = false;
        if (_remoteDetail == null) {
          _remoteError = userFacingApiMessage(error, fallback: '评价加载失败，请重试');
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingApiMessage(error, fallback: '详情加载失败，请重试')),
        ),
      );
    }
  }

  /// 登录态可能在本页面创建后才建立（弹层登录不会重建已推入的路由），
  /// 因此写操作直接尝试服务器，仅在返回 401 时引导登录。
  void _handleWriteError(Object error, {String fallback = '操作失败，请重试'}) {
    if (!mounted) return;
    if (_isUnauthorized(error)) {
      widget.onRequireAuth?.call();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userFacingApiMessage(error, fallback: fallback))),
    );
  }

  void _replaceToy(
    RankingToy toy, {
    bool syncWanted = true,
    bool syncOwned = true,
  }) {
    final detail = _remoteDetail;
    if (detail == null) return;
    final mergedToy = toy.copyWith(
      wanted: syncWanted ? toy.wanted : _wanted,
      owned: syncOwned ? toy.owned : _owned,
    );
    setState(() {
      _remoteDetail = detail.copyWith(toy: mergedToy);
      if (syncWanted) _wanted = mergedToy.wanted;
      if (syncOwned) _owned = mergedToy.owned;
    });
  }

  /// 管理员在详情页直接维护优惠券链接；空串表示清除。
  Future<void> _editCoupon() async {
    final controller = TextEditingController(
      text: _remoteDetail?.toy.couponUrl ?? item.couponUrl ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑优惠券链接'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: '粘贴 http(s) 链接，清空后保存即删除'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      final toy = await widget.repository!.setCouponUrl(
        toyId: item.id,
        couponUrl: result,
      );
      _replaceToy(toy);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.isEmpty ? '优惠券链接已清除' : '优惠券链接已更新')),
        );
      }
    } catch (error) {
      _handleWriteError(error, fallback: '优惠券链接保存失败，请重试');
    }
  }

  Future<void> _setWanted() async {
    if (_wantedSaving) return;
    final nextWanted = !_wanted;
    // 登录态可能在本页面创建后才建立（弹层登录不会重建已推入的路由），
    // 因此不用构造时的登录快照预判：直接尝试服务器，401/403 再回退本机清单。
    if (!_hasServer) {
      setState(() => _wanted = nextWanted);
      if (nextWanted && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RankingCouponPage(item: item),
          ),
        );
      }
      return;
    }

    final requestVersion = ++_wantedRequestVersion;
    setState(() {
      _wanted = nextWanted;
      _wantedSaving = true;
    });
    // 页面展示不依赖 wanted 写入结果；先完成用户操作，再后台同步状态。
    if (nextWanted && mounted) _openCouponPage(displayItem);
    try {
      final toy = await widget.repository!.setWanted(
        toyId: item.id,
        active: nextWanted,
      );
      if (mounted && requestVersion == _wantedRequestVersion) {
        _replaceToy(toy, syncOwned: false);
      }
    } catch (error) {
      if (!mounted || requestVersion != _wantedRequestVersion) return;
      if (_isAuthOrCapabilityDenied(error)) {
        // 游客或当前身份无投票权限：保留本机“想冲”标记，行为与游客一致。
        return;
      }
      setState(() => _wanted = !nextWanted);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiMessage(error))));
    } finally {
      if (mounted && requestVersion == _wantedRequestVersion) {
        setState(() => _wantedSaving = false);
      }
    }
  }

  Future<void> _setOwned() async {
    if (_ownedSaving) return;
    final nextOwned = !_owned;
    // 与 _setWanted 同策略：直接尝试服务器，401/403 回退本机“买过”标记。
    if (!_hasServer) {
      setState(() => _owned = nextOwned);
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RankingPurchasePage(item: item, owned: nextOwned),
          ),
        );
      }
      return;
    }

    final requestVersion = ++_ownedRequestVersion;
    setState(() {
      _owned = nextOwned;
      _ownedSaving = true;
    });
    try {
      final toy = await widget.repository!.setOwned(
        toyId: item.id,
        active: nextOwned,
      );
      if (mounted && requestVersion == _ownedRequestVersion) {
        _replaceToy(toy, syncWanted: false);
      }
    } catch (error) {
      if (!mounted || requestVersion != _ownedRequestVersion) return;
      if (_isAuthOrCapabilityDenied(error)) {
        // 游客或当前身份无服务器写入权限时保留本机标记，继续走本地体验。
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RankingPurchasePage(item: item, owned: nextOwned),
          ),
        );
        return;
      }
      setState(() => _owned = !nextOwned);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiMessage(error))));
    } finally {
      if (mounted && requestVersion == _ownedRequestVersion) {
        setState(() => _ownedSaving = false);
      }
    }
  }

  void _openCouponPage(RankingItem couponItem) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RankingCouponPage(item: couponItem),
      ),
    );
  }

  Future<void> _toggleSort() async {
    if (!_hasServer) {
      setState(() => _sortByWeight = !_sortByWeight);
      return;
    }
    final targetSortByWeight = !_sortByWeight;
    try {
      final detail = await widget.repository!.detail(
        item.id,
        commentSort: targetSortByWeight ? 'weight' : 'latest',
      );
      if (!mounted) return;
      setState(() {
        _sortByWeight = targetSortByWeight;
        _remoteDetail = detail;
        _commentsLoadMoreError = null;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingApiMessage(error, fallback: '排序切换失败，已保持原排序'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openRatingDialog() async {
    if (!_hasServer) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请连接服务器后评分')));
      return;
    }
    var selected = _remoteDetail?.toy.rating ?? 10;
    final score = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('给这款玩具评分'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$selected 分',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Slider(
                min: 1,
                max: 10,
                divisions: 9,
                value: selected.toDouble(),
                label: '$selected',
                onChanged: (value) =>
                    setDialogState(() => selected = value.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('提交评分'),
            ),
          ],
        ),
      ),
    );
    if (score == null) return;
    try {
      final toy = await widget.repository!.rate(toyId: item.id, score: score);
      _replaceToy(toy);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('评分已保存')));
      }
    } catch (error) {
      _handleWriteError(error, fallback: '评分保存失败');
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment(String value) async {
    if (value.trim().isEmpty) return;
    if (!_hasServer) {
      _commentController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请连接服务器后发表评论')));
      return;
    }
    try {
      final comment = await widget.repository!.createComment(
        toyId: item.id,
        content: value.trim(),
      );
      if (!mounted) return;
      final detail = _remoteDetail;
      if (detail != null) {
        setState(() {
          _remoteDetail = detail.copyWith(
            comments: [comment, ...detail.comments],
          );
        });
      }
      _commentController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('评论已提交')));
    } catch (error) {
      _handleWriteError(error, fallback: '评论提交失败');
    }
  }

  Future<void> _toggleServerCommentLike(RankingToyComment comment) async {
    if (!_hasServer) return;
    try {
      final count = await widget.repository!.setCommentLike(
        commentId: comment.id,
        active: !comment.isLiked,
      );
      if (!mounted || _remoteDetail == null) return;
      final nextLiked = !comment.isLiked;
      final nextCount = count > 0
          ? count
          : (nextLiked
                ? comment.likeCount + 1
                : (comment.likeCount - 1).clamp(0, 1 << 30).toInt());
      final comments = _remoteDetail!.comments
          .map(
            (item) => item.id == comment.id
                ? item.copyWith(likeCount: nextCount, isLiked: nextLiked)
                : item,
          )
          .toList();
      setState(() {
        _remoteDetail = _remoteDetail!.copyWith(comments: comments);
      });
    } catch (error) {
      _handleWriteError(error, fallback: '点赞失败，请重试');
    }
  }

  void _showRankingCommentMenu(RankingToyComment comment) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('复制内容'),
            onTap: () {
              Navigator.pop(sheetContext);
              Clipboard.setData(ClipboardData(text: comment.content));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadMoreServerComments() async {
    final detail = _remoteDetail;
    final cursor = detail?.commentsNextCursor;
    if (detail == null || cursor == null || _commentsLoadingMore) return;
    setState(() {
      _commentsLoadingMore = true;
      _commentsLoadMoreError = null;
    });
    try {
      final page = await widget.repository!.listComments(
        toyId: item.id,
        sort: _sortByWeight ? 'weight' : 'latest',
        cursor: cursor,
      );
      if (!mounted) return;
      final existing = detail.comments.map((comment) => comment.id).toSet();
      final comments = [...detail.comments];
      for (final comment in page.items) {
        if (comment.parentId == null && existing.add(comment.id)) {
          comments.add(comment);
        }
      }
      setState(() {
        _remoteDetail = detail.copyWith(
          comments: comments,
          commentsNextCursor: page.nextCursor,
          commentsHasMore: page.hasMore && page.nextCursor != cursor,
        );
        _commentsLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _commentsLoadingMore = false;
        _commentsLoadMoreError = userFacingApiMessage(
          error,
          fallback: '更多评价加载失败，点击重试',
        );
      });
    }
  }

  Future<void> _openRankingThread(RankingToyComment root) async {
    final repository = widget.repository;
    if (repository == null) return;
    var changed = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RankingCommentThreadSheet(
        rootComment: root,
        repository: repository,
        isAuthenticated: widget.isAuthenticated,
        canComment: widget.canComment,
        canLike: widget.canLike,
        onRequireAuth: widget.onRequireAuth,
        onReply: (target, content) => repository.createComment(
          toyId: item.id,
          content: content,
          parentId: target.id,
          replyToUserId: target.authorId,
        ),
        onToggleLike: (comment, active) =>
            repository.setCommentLike(commentId: comment.id, active: active),
        onChanged: () => changed = true,
      ),
    );
    if (changed && mounted) {
      await _loadRemoteDetail();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    resizeToAvoidBottomInset: true,
    body: SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Column(
            children: [
              _DetailTopBar(
                onBack: () => Navigator.of(context).maybePop(),
                onShare: () async {
                  final shareUrl = AppLinks.ranking(
                    item.id.isNotEmpty ? item.id : '${item.rank}',
                  );
                  try {
                    await Share.share(shareUrl, subject: '分享榜单商品');
                  } catch (_) {
                    await Clipboard.setData(ClipboardData(text: shareUrl));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('系统分享不可用，商品链接已复制')),
                      );
                    }
                  }
                },
              ),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  thickness: 3,
                  radius: const Radius.circular(3),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 78),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailProductIntro(item: displayItem),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                          child: Text(
                            _description,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 15,
                              height: 1.55,
                            ),
                          ),
                        ),
                        Semantics(
                          button: _hasServer,
                          label: '点击评分，当前 $_score 分',
                          child: InkWell(
                            onTap: _hasServer ? _openRatingDialog : null,
                            borderRadius: BorderRadius.circular(16),
                            child: _DetailRatingCard(
                              item: displayItem,
                              ratingDistribution:
                                  _remoteDetail?.ratingDistribution ??
                                  item.ratingDistribution,
                            ),
                          ),
                        ),
                        _DetailActions(
                          wanted: _wanted,
                          owned: _owned,
                          wantCount: _wantCount,
                          reviewCount: _reviewCount,
                          onWant: _setWanted,
                          onOwn: _setOwned,
                        ),
                        if (widget.canManageRanking &&
                            widget.repository != null &&
                            _hasServer)
                          _DetailCouponAdminCard(
                            couponUrl: displayItem.couponUrl,
                            onEdit: _editCoupon,
                          ),
                        _ReviewSection(
                          sortByWeight: _sortByWeight,
                          comments: _serverComments,
                          useMock: !_hasServer,
                          loading: _remoteLoading,
                          errorMessage: _remoteError,
                          loadingMore: _commentsLoadingMore,
                          hasMore: _remoteDetail?.commentsHasMore ?? false,
                          loadMoreError: _commentsLoadMoreError,
                          onToggleSort: _toggleSort,
                          onLoadMore: _remoteDetail == null
                              ? () {
                                  _loadRemoteDetail();
                                }
                              : _loadMoreServerComments,
                          onLike: _toggleServerCommentLike,
                          onReply: _openRankingThread,
                          onViewReplies: _openRankingThread,
                          onMore: (comment) => _showRankingCommentMenu(comment),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _DetailCommentBar(
              controller: _commentController,
              reviewCount: _reviewCount,
              wantCount: _wantCount,
              onSubmitted: _submitComment,
            ),
          ),
        ],
      ),
    ),
  );
}

/// 游客点击“想冲”后展示的优惠券入口页。
class RankingCouponPage extends StatelessWidget {
  const RankingCouponPage({super.key, required this.item});

  final RankingItem item;

  Future<void> _openCoupon(BuildContext context) async {
    final link = item.couponUrl;
    if (link == null || link.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时没找到优惠券')));
      return;
    }
    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      await Clipboard.setData(ClipboardData(text: link));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开浏览器，优惠链接已复制')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('想冲清单')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: _rankingImage(
                  item,
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              item.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF182C49),
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '已加入想冲清单，可直接领取或查看优惠。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF718096), fontSize: 13),
            ),
            const SizedBox(height: 28),
            if (item.couponUrl != null && item.couponUrl!.isNotEmpty) ...[
              SelectableText(
                item.couponUrl!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF55739A), fontSize: 12),
              ),
              const SizedBox(height: 12),
            ] else
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  '暂时没找到优惠券',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8A96A9), fontSize: 12),
                ),
              ),
            FilledButton.icon(
              onPressed: () => _openCoupon(context),
              icon: const Icon(Icons.local_offer_outlined),
              label: const Text('打开优惠券链接'),
            ),
            TextButton.icon(
              onPressed: item.couponUrl == null
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: item.couponUrl!),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('优惠券链接已复制')),
                        );
                      }
                    },
              icon: const Icon(Icons.copy_outlined, size: 17),
              label: const Text('复制链接'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 游客点击“买过”后展示的购买状态页。
class RankingPurchasePage extends StatelessWidget {
  const RankingPurchasePage({
    super.key,
    required this.item,
    required this.owned,
  });

  final RankingItem item;
  final bool owned;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('购买记录')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              owned ? Icons.check_circle_rounded : Icons.undo_rounded,
              size: 58,
              color: owned ? const Color(0xFFF76591) : const Color(0xFF8A96A9),
            ),
            const SizedBox(height: 18),
            Text(
              owned ? '已标记为买过' : '已取消“买过”标记',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF182C49),
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF718096), fontSize: 14),
            ),
            const SizedBox(height: 22),
            const Text(
              '游客标记仅保存在当前设备；登录账号后可同步并发布评价。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8A96A9), fontSize: 12),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('返回商品详情'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({required this.onBack, required this.onShare});

  final VoidCallback onBack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: Row(
      children: [
        SizedBox(
          width: 54,
          height: 54,
          child: Tooltip(
            message: '返回',
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: Color(0xFF2D3441),
              ),
            ),
          ),
        ),
        const Expanded(
          child: Center(
            child: Icon(Icons.toys, size: 23, color: Color(0xFF1D2A42)),
          ),
        ),
        SizedBox(
          width: 54,
          height: 54,
          child: Tooltip(
            message: '分享',
            child: IconButton(
              onPressed: onShare,
              icon: const Icon(
                Icons.ios_share_outlined,
                size: 19,
                color: Color(0xFF556176),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 管理员在商品详情页内维护优惠券链接的入口卡片。
class _DetailCouponAdminCard extends StatelessWidget {
  const _DetailCouponAdminCard({required this.couponUrl, required this.onEdit});

  final String? couponUrl;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasCoupon = couponUrl != null && couponUrl!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 24, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8ECF2)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.local_offer_outlined,
              size: 18,
              color: Color(0xFF55739A),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '优惠券链接（仅管理员可见）',
                    style: TextStyle(
                      color: Color(0xFF2D3441),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasCoupon ? couponUrl! : '暂未设置，点击“添加”为该商品配券',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8A96A9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onEdit,
              icon: Icon(
                hasCoupon ? Icons.edit_outlined : Icons.add_link_outlined,
                size: 15,
              ),
              label: Text(hasCoupon ? '编辑' : '添加'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF55739A),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailProductIntro extends StatelessWidget {
  const _DetailProductIntro({required this.item});

  final RankingItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 9, 24, 14),
    child: SizedBox(
      height: 142,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 112,
            child: _rankingImage(
              item,
              width: 112,
              height: 142,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF12243E),
                      fontSize: 21,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${item.merchant} · ${item.releaseYear}',
                    style: const TextStyle(
                      color: Color(0xFF60708A),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: item.tags.map(_DetailTag.new).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DetailTag extends StatelessWidget {
  const _DetailTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F5),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        '#$label',
        style: const TextStyle(
          color: Color(0xFFF26791),
          fontSize: 10,
          height: 1.05,
        ),
      ),
    ),
  );
}

class _DetailRatingCard extends StatelessWidget {
  const _DetailRatingCard({
    required this.item,
    this.ratingDistribution = const {},
  });

  final RankingItem item;
  final Map<int, int> ratingDistribution;

  @override
  Widget build(BuildContext context) {
    final distribution = ratingDistribution.isNotEmpty
        ? ratingDistribution
        : item.ratingDistribution;
    final total = distribution.values.fold<int>(0, (s, e) => s + e);
    final levels = [
      (5, ((distribution[10] ?? 0) + (distribution[9] ?? 0))),
      (4, ((distribution[8] ?? 0) + (distribution[7] ?? 0))),
      (3, ((distribution[6] ?? 0) + (distribution[5] ?? 0))),
      (2, ((distribution[4] ?? 0) + (distribution[3] ?? 0))),
      (1, ((distribution[2] ?? 0) + (distribution[1] ?? 0))),
    ];

    return Container(
      height: 156,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      padding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 116,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 26),
                  child: Text(
                    '酱友评分',
                    style: TextStyle(
                      color: Color(0xFF66738A),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  item.score,
                  style: const TextStyle(
                    color: Color(0xFFF7618E),
                    fontSize: 48,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Row(
                  children: List.generate(
                    5,
                    (index) => const Padding(
                      padding: EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.favorite,
                        size: 14,
                        color: Color(0xFFF7618E),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: total == 0
                ? const Center(
                    child: Text(
                      '暂无评分分布',
                      style: TextStyle(color: Color(0xFF7E8AA0), fontSize: 12),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final entry in levels)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _RatingBar(
                            level: entry.$1,
                            value: entry.$2 / total,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RatingBar extends StatelessWidget {
  const _RatingBar({required this.level, required this.value});

  final int level;
  final double value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 18,
        child: Text(
          '$level',
          style: const TextStyle(color: Color(0xFF7E8AA0), fontSize: 12),
        ),
      ),
      Expanded(
        child: SizedBox(
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.white),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: const ColoredBox(color: Color(0xFFF7618E)),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.wanted,
    required this.owned,
    required this.wantCount,
    required this.reviewCount,
    required this.onWant,
    required this.onOwn,
  });

  final bool wanted;
  final bool owned;
  final String wantCount;
  final String reviewCount;
  final VoidCallback onWant;
  final VoidCallback onOwn;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
    child: Row(
      children: [
        Expanded(
          child: _DetailActionButton(
            label: wanted ? '已想冲' : '想冲',
            count: '$wantCount人想冲',
            icon: wanted ? Icons.favorite : Icons.favorite_border_rounded,
            filled: wanted,
            onTap: onWant,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _DetailActionButton(
            label: owned ? '已买过' : '买过',
            count: '$reviewCount人评分',
            icon: Icons.edit_outlined,
            filled: true,
            onTap: onOwn,
          ),
        ),
      ],
    ),
  );
}

class _DetailActionButton extends StatelessWidget {
  const _DetailActionButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final String count;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: filled ? const Color(0xFFF76591) : const Color(0xFFFFF0F5),
    borderRadius: BorderRadius.circular(13),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        height: 45,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: filled ? Colors.white : const Color(0xFFF76591),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: filled ? Colors.white : const Color(0xFFF76591),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Positioned(
              right: 10,
              bottom: 5,
              child: Text(
                count,
                style: TextStyle(
                  color: filled
                      ? Colors.white.withValues(alpha: 0.9)
                      : const Color(0xFFF76591),
                  fontSize: 8,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.sortByWeight,
    required this.onToggleSort,
    this.comments,
    this.useMock = false,
    this.loading = false,
    this.errorMessage,
    this.loadingMore = false,
    this.hasMore = false,
    this.loadMoreError,
    this.onLoadMore,
    this.onLike,
    this.onReply,
    this.onViewReplies,
    this.onMore,
  });

  final bool sortByWeight;
  final VoidCallback onToggleSort;
  final List<RankingToyComment>? comments;
  final bool useMock;
  final bool loading;
  final String? errorMessage;
  final bool loadingMore;
  final bool hasMore;
  final String? loadMoreError;
  final VoidCallback? onLoadMore;
  final ValueChanged<RankingToyComment>? onLike;
  final ValueChanged<RankingToyComment>? onReply;
  final ValueChanged<RankingToyComment>? onViewReplies;
  final ValueChanged<RankingToyComment>? onMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 37, 24, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              '评价',
              style: TextStyle(
                color: Color(0xFF142A48),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onToggleSort,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8A96A9),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(sortByWeight ? '按权重排序' : '按时间排序'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (comments == null && useMock) ...[
          const _ReviewCard(
            user: '菜菜M',
            likes: '8',
            content: 'A酱的慢玩断折作，比琉璃子好比琉璃子贵就是没有琉璃子陪伴的回忆而已（悲…）',
            reply:
                '杂鱼萌萌(538793014)：大佬你好，这张图在店铺里对应的是二代款［普通版］，还有另一张是二代［经典版］，但是是另一张图，应该是哪个大佬',
            replyDate: '07-29',
            avatarColor: Color(0xFFFFE7B6),
            level: 3,
            authorRating: 9,
          ),
          const _ReviewCard(
            user: '杂鱼萌萌',
            likes: '3',
            content: '这个盒子的好用一点，比较软，锻炼和练射时长选这个版本就行了。礼盒版是周边多，配送点东西，但是胶体是一样的。',
            reply: null,
            replyDate: null,
            avatarColor: Color(0xFFE3EEFF),
            level: 2,
            authorRating: 8,
          ),
        ] else if (comments == null && loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: CommentSkeleton(itemCount: 2),
          )
        else if (comments == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                Text(
                  errorMessage ?? '评价加载失败，请重试',
                  style: const TextStyle(color: Color(0xFF8A96A9)),
                ),
                const SizedBox(height: 6),
                TextButton(onPressed: onLoadMore, child: const Text('点击重试')),
              ],
            ),
          )
        else if (comments!.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              '还没有评价，来留下第一条吧',
              style: TextStyle(color: Color(0xFF8A96A9)),
            ),
          )
        else
          ..._buildServerCards(comments!),
        if (comments != null && comments!.isNotEmpty && hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Center(
              child: loadMoreError != null
                  ? TextButton(
                      onPressed: onLoadMore,
                      child: Text(loadMoreError!),
                    )
                  : loadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: onLoadMore,
                      child: const Text('加载更多评价'),
                    ),
            ),
          ),
      ],
    ),
  );

  List<Widget> _buildServerCards(List<RankingToyComment> items) {
    final childrenByParent = <String, List<RankingToyComment>>{};
    for (final item in items) {
      final parentId = item.parentId;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(item);
      }
    }
    final roots = items.where((item) => item.parentId == null).toList();
    return roots
        .map(
          (comment) => _ReviewCard.server(
            comment: comment,
            replies: childrenByParent[comment.id] ?? const [],
            onLike: onLike == null ? null : () => onLike!(comment),
            onReply: onReply == null ? null : () => onReply!(comment),
            onReplyTo: onReply,
            onViewReplies: onViewReplies == null
                ? null
                : () => onViewReplies!(comment),
            onMore: onMore == null ? null : () => onMore!(comment),
          ),
        )
        .toList();
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.user,
    required this.likes,
    required this.content,
    required this.reply,
    required this.replyDate,
    required this.avatarColor,
    this.level = 1,
    this.authorRating,
  }) : liked = false,
       media = const [],
       avatarUrl = null,
       onLike = null,
       replies = const [],
       onReply = null,
       onReplyTo = null,
       onViewReplies = null,
       onMore = null,
       commentReplyCount = 0;

  _ReviewCard.server({
    required RankingToyComment comment,
    required this.onLike,
    this.replies = const [],
    this.onReply,
    this.onReplyTo,
    this.onViewReplies,
    this.onMore,
  }) : user = comment.nickname.isEmpty ? comment.username : comment.nickname,
       likes = '${comment.likeCount}',
       content = comment.content,
       media = comment.media,
       avatarUrl = comment.avatarUrl,
       reply = null,
       replyDate = null,
       avatarColor = const Color(0xFFE3EEFF),
       liked = comment.isLiked,
       level = comment.level,
       authorRating = comment.authorRating,
       commentReplyCount = comment.replyCount;

  final String user;
  final String likes;
  final String content;
  final List<RankingToyCommentMedia> media;
  final String? avatarUrl;
  final String? reply;
  final String? replyDate;
  final Color avatarColor;
  final bool liked;
  final int level;
  final int? authorRating;
  final int commentReplyCount;
  final VoidCallback? onLike;
  final List<RankingToyComment> replies;
  final VoidCallback? onReply;
  final ValueChanged<RankingToyComment>? onReplyTo;
  final VoidCallback? onViewReplies;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: avatarColor,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE8ECF2)),
          ),
          clipBehavior: Clip.antiAlias,
          child: avatarUrl != null && avatarUrl!.isNotEmpty
              ? AppNetworkImage(
                  url: avatarUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_) => const Icon(
                    Icons.person_outline_rounded,
                    size: 22,
                    color: Color(0xFF7D8BA3),
                  ),
                )
              : const Icon(
                  Icons.person_outline_rounded,
                  size: 22,
                  color: Color(0xFF7D8BA3),
                ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    user,
                    style: const TextStyle(
                      color: Color(0xFF102844),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4F8F1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'LV$level',
                      style: const TextStyle(
                        color: Color(0xFF38AD8B),
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (onLike == null)
                    Icon(
                      Icons.thumb_up_alt_outlined,
                      size: 18,
                      color: liked
                          ? const Color(0xFFF76591)
                          : const Color(0xFFAAB2C0),
                    )
                  else
                    InkWell(
                      onTap: onLike,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          liked
                              ? Icons.thumb_up_alt_rounded
                              : Icons.thumb_up_alt_outlined,
                          size: 18,
                          color: liked
                              ? const Color(0xFFF76591)
                              : const Color(0xFFAAB2C0),
                        ),
                      ),
                    ),
                  const SizedBox(width: 5),
                  Text(
                    likes,
                    style: const TextStyle(
                      color: Color(0xFF7D899D),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  ...List.generate(5, (index) {
                    final filled =
                        authorRating == null ||
                        index < ((authorRating! + 1) ~/ 2);
                    return Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        filled ? Icons.favorite : Icons.favorite_border_rounded,
                        size: 13,
                        color: const Color(0xFFF76591),
                      ),
                    );
                  }),
                  if (authorRating != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$authorRating分',
                      style: const TextStyle(
                        color: Color(0xFFF76591),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 7),
              GestureDetector(
                onTap: onReply,
                child: Text(
                  content,
                  style: const TextStyle(
                    color: Color(0xFF203C60),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
              if (media.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var index = 0; index < media.length; index++)
                        GestureDetector(
                          onTap: () => CommentImageViewer.open(
                            context,
                            imageUrls: media.map((item) => item.url).toList(),
                            initialIndex: index,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AppNetworkImage(
                              url: media[index].url,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (_) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (onReply != null)
                TextButton(
                  onPressed: onReply,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(38, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('回复'),
                ),
              if (onViewReplies != null &&
                  (commentReplyCount > 0 || replies.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: InkWell(
                    onTap: onViewReplies,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 5,
                        horizontal: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '查看 ${commentReplyCount > 0 ? commentReplyCount : replies.length} 条回复',
                            style: const TextStyle(
                              color: Color(0xFF3C70B7),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: Color(0xFF3C70B7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (onMore != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: CommentMoreButton(onPressed: onMore!),
                ),
              if (reply != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FB),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: reply,
                          style: const TextStyle(
                            color: Color(0xFF3C70B7),
                            fontSize: 12,
                            height: 1.65,
                          ),
                        ),
                        TextSpan(
                          text: '  $replyDate',
                          style: const TextStyle(
                            color: Color(0xFF9AA5B7),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _DetailCommentBar extends StatelessWidget {
  const _DetailCommentBar({
    required this.controller,
    required this.reviewCount,
    required this.wantCount,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String reviewCount;
  final String wantCount;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 8,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: onSubmitted,
                textInputAction: TextInputAction.send,
                style: const TextStyle(color: Color(0xFF233B5B), fontSize: 13),
                decoration: InputDecoration(
                  hintText: '来，说点什么吧!',
                  hintStyle: const TextStyle(
                    color: Color(0xFFAEB8C6),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF4F5F8),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              reviewCount,
              style: const TextStyle(color: Color(0xFF78869A), fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 17,
              color: Color(0xFF6F7B8E),
            ),
            const SizedBox(width: 9),
            Text(
              wantCount,
              style: const TextStyle(color: Color(0xFF78869A), fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.favorite_border_rounded,
              size: 20,
              color: Color(0xFF59667A),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.item, required this.onTap});

  final RankingItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    onTap: onTap,
    label: '第${item.rank}名 ${item.name}，${item.score} 分',
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 90,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF3F4F6)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 23,
              child: Text(
                '${item.rank}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: item.rank <= 3
                      ? const Color(0xFFE7A04C)
                      : const Color(0xFF9CA3AF),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _rankingImage(
                item,
                width: 64,
                height: 64,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF222222),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.hot,
                        style: const TextStyle(
                          color: Color(0xFFB4B4B4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < item.tags.length;
                          index++
                        ) ...[
                          _TagChip(item.tags[index]),
                          if (index != item.tags.length - 1)
                            const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        item.ratings,
                        style: const TextStyle(
                          color: Color(0xFFB4B4B4),
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${item.score} 分',
                        style: const TextStyle(
                          color: Color(0xFFEA6D93),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F4),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: Text(
        '#$label',
        style: const TextStyle(
          color: Color(0xFFEB86A4),
          fontSize: 9,
          height: 1.05,
        ),
      ),
    ),
  );
}
