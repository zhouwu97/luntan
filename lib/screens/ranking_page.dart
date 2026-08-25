import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/ranking_repository.dart';
import '../domain/models.dart' show relativeTimeLabel;

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
}

const _mainRankingItems = <RankingItem>[
  RankingItem(
    rank: 2,
    name: '樱川爱 二代',
    hot: '401人想冲',
    tags: ['细密颗粒', '肉褶延续', '极致慢玩'],
    ratings: '17人评分',
    score: '9.9',
    asset: 'assets/ranking/thumb_02.webp',
    merchant: 'TMT',
    releaseYear: 2026,
    description:
        '樱2软版本基本延续了前作的慢玩设定。设计结构网状结构+细密绒粒,完全属于纯新手属性的舒适按摩区，末尾方块状奇袭冲刺区也几乎拒绝一切强硬度挑战。相比琉璃子,此作才更能定义A酱最适合新手的杯子！',
  ),
  RankingItem(
    rank: 3,
    name: '鱼头',
    hot: '497人想冲',
    tags: ['猎奇', '高性价比', '传说神器'],
    ratings: '90人评分',
    score: '9.1',
    asset: 'assets/ranking/thumb_03.webp',
  ),
  RankingItem(
    rank: 4,
    name: '元气教练',
    hot: '284人想冲',
    tags: ['强烈挤压', '脂软工艺', '后入抓握'],
    ratings: '6人评分',
    score: '9.3',
    asset: 'assets/ranking/thumb_04.webp',
  ),
  RankingItem(
    rank: 5,
    name: '神代雪乃',
    hot: '148人想冲',
    tags: ['顶级材料', '一字开腿', '冷门神作'],
    ratings: '11人评分',
    score: '9.8',
    asset: 'assets/ranking/thumb_05.jpg',
  ),
  RankingItem(
    rank: 6,
    name: '星野爱丽丝 二代',
    hot: '91人想冲',
    tags: ['慢玩大臀', '定制周边', '收藏属性'],
    ratings: '4人评分',
    score: '10',
    asset: 'assets/ranking/thumb_06.webp',
  ),
  RankingItem(
    rank: 7,
    name: '奈奈子 二代',
    hot: '430人想冲',
    tags: ['重装包裹', '柔厚肉壁', '渐进式'],
    ratings: '16人评分',
    score: '9.9',
    asset: 'assets/ranking/thumb_07.webp',
  ),
  RankingItem(
    rank: 8,
    name: '双穴爱莉',
    hot: '365人想冲',
    tags: ['双穴包裹', '仿真慢玩', '舒适探索'],
    ratings: '14人评分',
    score: '9.1',
    asset: 'assets/ranking/thumb_08.webp',
  ),
  RankingItem(
    rank: 9,
    name: '水着琉璃子',
    hot: '241人想冲',
    tags: ['A酱首选', '极易入门', '软呼呼'],
    ratings: '15人评分',
    score: '8.5',
    asset: 'assets/ranking/thumb_09.webp',
  ),
  RankingItem(
    rank: 10,
    name: '可可狼姬',
    hot: '464人想冲',
    tags: ['黑皮', '榨汁强刮', '兽耳女仆'],
    ratings: '42人评分',
    score: '9',
    asset: 'assets/ranking/thumb_10.webp',
  ),
  RankingItem(
    rank: 11,
    name: '皮小鬼 二代',
    hot: '301人想冲',
    tags: ['真实回弹', '肉感', '毕业臀模'],
    ratings: '33人评分',
    score: '7.9',
    asset: 'assets/ranking/thumb_11.webp',
  ),
  RankingItem(
    rank: 12,
    name: '狐狐子',
    hot: '281人想冲',
    tags: ['一字马', '松鼠娘', '内部铆钉'],
    ratings: '15人评分',
    score: '9.7',
    asset: 'assets/ranking/thumb_12.png',
  ),
  RankingItem(
    rank: 13,
    name: '幻乳龙娘',
    hot: '186人想冲',
    tags: ['巨乳巨臀', '重型泰坦', '阻塞黏腻'],
    ratings: '11人评分',
    score: '9.4',
    asset: 'assets/ranking/thumb_13.webp',
  ),
  RankingItem(
    rank: 14,
    name: '小鬼魔皇',
    hot: '297人想冲',
    tags: ['高刺榨汁', '重型机甲', '水波肉臀'],
    ratings: '23人评分',
    score: '9',
    asset: 'assets/ranking/thumb_14.webp',
  ),
  RankingItem(
    rank: 15,
    name: '赤鸢',
    hot: '36人想冲',
    tags: ['爆乳脂软', '大臀', '机械横纹'],
    ratings: '5人评分',
    score: '9.2',
    asset: 'assets/ranking/thumb_15.webp',
  ),
  RankingItem(
    rank: 16,
    name: '五宫豚娘物语',
    hot: '145人想冲',
    tags: ['猎奇狂', '福瑞控', '海豚仿生'],
    ratings: '11人评分',
    score: '7.9',
    asset: 'assets/ranking/thumb_16.webp',
  ),
  RankingItem(
    rank: 17,
    name: '白丝壁女 二代',
    hot: '91人想冲',
    tags: ['重力负压', '暴力内腔', '加硬'],
    ratings: '7人评分',
    score: '5.9',
    asset: 'assets/ranking/thumb_17.webp',
  ),
  RankingItem(
    rank: 18,
    name: '宫濑 Soft',
    hot: '426人想冲',
    tags: ['脂软材质', '细密包裹', '超软慢玩'],
    ratings: '26人评分',
    score: '8.7',
    asset: 'assets/ranking/thumb_18.webp',
  ),
  RankingItem(
    rank: 19,
    name: '千美',
    hot: '61人想冲',
    tags: ['直筒型', '极致肉厚', '被动包裹'],
    ratings: '5人评分',
    score: '9',
    asset: 'assets/ranking/thumb_19.webp',
  ),
  RankingItem(
    rank: 20,
    name: '水野 2',
    hot: '429人想冲',
    tags: ['体脂水感', '温和型', '顺滑贴合'],
    ratings: '5人评分',
    score: '9.1',
    asset: 'assets/ranking/thumb_20.webp',
  ),
];

const _slowRankingItems = <RankingItem>[
  RankingItem(
    rank: 1,
    name: '樱川爱 二代',
    hot: '401人想冲',
    tags: ['细密颗粒', '肉褶延续', '极致慢玩'],
    ratings: '17人评分',
    score: '9.9',
    asset: 'assets/ranking/thumb_02.webp',
  ),
  RankingItem(
    rank: 2,
    name: '双穴爱莉',
    hot: '365人想冲',
    tags: ['双穴包裹', '仿真慢玩', '舒适探索'],
    ratings: '14人评分',
    score: '9.1',
    asset: 'assets/ranking/thumb_08.webp',
  ),
  RankingItem(
    rank: 3,
    name: '宫濑 Soft',
    hot: '426人想冲',
    tags: ['脂软材质', '细密包裹', '超软慢玩'],
    ratings: '26人评分',
    score: '8.7',
    asset: 'assets/ranking/thumb_18.webp',
  ),
  RankingItem(
    rank: 4,
    name: '水着琉璃子',
    hot: '241人想冲',
    tags: ['A酱首选', '极易入门', '软呼呼'],
    ratings: '15人评分',
    score: '8.5',
    asset: 'assets/ranking/thumb_09.webp',
  ),
  RankingItem(
    rank: 5,
    name: '巴布密着 Big',
    hot: '44人想冲',
    tags: ['母性包裹', '肉厚吸裹', '慢玩神作'],
    ratings: '3人评分',
    score: '9.7',
    asset: 'assets/ranking/slow_05.webp',
  ),
  RankingItem(
    rank: 6,
    name: '红绳姐姐',
    hot: '25人想冲',
    tags: ['极致偏软', '末端子宫', '螺旋包裹'],
    ratings: '4人评分',
    score: '9.8',
    asset: 'assets/ranking/slow_06.webp',
  ),
];

const _topRankingItem = RankingItem(
  id: 'toy-butter-2',
  rank: 1,
  name: '黄油小姐 二代',
  hot: '本周热门',
  tags: ['奶香体质', '软糯入门', '果冻包裹'],
  ratings: '热门榜首',
  score: '8.7',
  asset: 'assets/ranking/hero.webp',
  merchant: 'COC',
  releaseYear: 2025,
  description: '相较前作，黄油小姐2完成了一次华丽的材质蜕变。奶香味提升，肉质的软糯度提升极佳。大结构轨道带来的异物包裹感实战体验飙升。',
);

const _rankingTabs = ['综合热榜', '慢玩入门', '进阶训练', '超高刺激', '榨汁玩具'];

class RankingPage extends StatefulWidget {
  const RankingPage({
    super.key,
    this.repository,
    this.isAuthenticated = false,
    this.onRequireAuth,
  });

  final RankingRepository? repository;
  final bool isAuthenticated;
  final VoidCallback? onRequireAuth;

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  int _selectedTab = 0;
  int _selectedCategory = 0;
  List<RankingItem>? _remoteItems;

  static const _slowNames = <String>{
    '樱川爱 二代',
    '双穴爱莉',
    '宫濑 Soft',
    '水着琉璃子',
    '巴布密着 Big',
    '红绳姐姐',
  };

  @override
  void initState() {
    super.initState();
    if (widget.repository != null) _loadRemoteRanking();
  }

  Future<void> _loadRemoteRanking() async {
    try {
      final products = await widget.repository!.list();
      if (!mounted || products.isEmpty) return;
      setState(() {
        _remoteItems = products.map(_itemFromRemote).toList();
      });
    } catch (_) {
      // 服务端暂时不可用时保留已缓存的视觉结构，进入详情仍会提示重试。
    }
  }

  RankingItem _itemFromRemote(RankingToy toy) {
    final score = toy.score == toy.score.roundToDouble()
        ? toy.score.toStringAsFixed(0)
        : toy.score.toStringAsFixed(1);
    final asset = toy.rank == 1
        ? 'assets/ranking/hero.webp'
        : 'assets/ranking/${toy.assetKey}';
    return RankingItem(
      id: toy.id,
      rank: toy.rank,
      name: toy.name,
      hot: '${toy.wantCount}人想冲',
      tags: toy.tags,
      ratings: '${toy.ratingCount}人评分',
      score: score,
      asset: asset,
      merchant: toy.merchant,
      releaseYear: toy.releaseYear,
      description: toy.description,
    );
  }

  List<RankingItem> get _items => _selectedTab == 1
      ? (_remoteItems == null
            ? _slowRankingItems
            : _remoteItems!
                  .where((item) => _slowNames.contains(item.name))
                  .toList())
      : (_remoteItems == null
            ? _mainRankingItems
            : _remoteItems!.where((item) => item.rank != 1).toList());

  RankingItem get _topItem {
    if (_remoteItems == null) return _topRankingItem;
    return _remoteItems!.firstWhere(
      (item) => item.rank == 1,
      orElse: () => _topRankingItem,
    );
  }

  void _openRankingItem(RankingItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RankingItemDetailPage(
          item: item,
          repository: widget.repository,
          isAuthenticated: widget.isAuthenticated,
          onRequireAuth: widget.onRequireAuth,
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
          _RankingHeader(onBack: () => Navigator.of(context).maybePop()),
          Expanded(child: _rankingScrollView()),
        ],
      ),
    ),
  );

  Widget _rankingScrollView() => ListView(
    children: [
      _RankingTabs(
        selectedIndex: _selectedTab,
        onTap: (index) => setState(() => _selectedTab = index),
      ),
      _CategoryGrid(
        selectedIndex: _selectedCategory,
        onTap: (index) => setState(() => _selectedCategory = index),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _selectedTab == 0
            ? Column(
                children: [
                  _TopRankingCard(
                    item: _topItem,
                    onTap: () => _openRankingItem(_topItem),
                  ),
                  const SizedBox(height: 10),
                  ..._items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RankingCard(
                        item: item,
                        onTap: () => _openRankingItem(item),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  ..._items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RankingCard(
                        item: item,
                        onTap: () => _openRankingItem(item),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    ],
  );
}

class _RankingHeader extends StatelessWidget {
  const _RankingHeader({required this.onBack});

  final VoidCallback onBack;

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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: Color(0xFF9CA3AF),
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '搜索：魅魔、大魔王、慢玩...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFFF4F93),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22FF4F93),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 19),
          ),
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
                  Image.asset('assets/ranking/hero.webp', fit: BoxFit.cover),
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
    this.onRequireAuth,
  });

  final RankingItem item;
  final RankingRepository? repository;
  final bool isAuthenticated;
  final VoidCallback? onRequireAuth;

  @override
  State<RankingItemDetailPage> createState() => _RankingItemDetailPageState();
}

class _RankingItemDetailPageState extends State<RankingItemDetailPage> {
  static const _ink = Color(0xFF182C49);

  final _commentController = TextEditingController();
  bool _wanted = false;
  bool _owned = false;
  bool _sortByWeight = true;
  RankingToyComment? _replyTarget;
  RankingToyDetail? _remoteDetail;

  RankingItem get item => widget.item;

  RankingItem get displayItem {
    final toy = _remoteDetail?.toy;
    if (toy == null) return item;
    return RankingItem(
      id: toy.id,
      rank: toy.rank,
      name: toy.name,
      hot: '${toy.wantCount}人想冲',
      tags: toy.tags,
      ratings: '${toy.ratingCount}人评分',
      score: _scoreText(toy.score),
      asset: item.asset,
      merchant: toy.merchant,
      releaseYear: toy.releaseYear,
      description: toy.description,
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
    try {
      final detail = await widget.repository!.detail(
        item.id,
        commentSort: _sortByWeight ? 'weight' : 'latest',
      );
      if (!mounted) return;
      setState(() {
        _remoteDetail = detail;
        _wanted = detail.toy.wanted;
        _owned = detail.toy.owned;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingApiMessage(error, fallback: '详情加载失败，请重试')),
        ),
      );
    }
  }

  bool _requireInteractionAuth() {
    if (!_hasServer || widget.isAuthenticated) return true;
    widget.onRequireAuth?.call();
    return false;
  }

  void _replaceToy(RankingToy toy) {
    final detail = _remoteDetail;
    if (detail == null) return;
    setState(() {
      _remoteDetail = RankingToyDetail(
        toy: toy,
        comments: detail.comments,
        commentSort: detail.commentSort,
      );
      _wanted = toy.wanted;
      _owned = toy.owned;
    });
  }

  Future<void> _setWanted() async {
    if (!_requireInteractionAuth()) return;
    if (!_hasServer) {
      setState(() => _wanted = !_wanted);
      return;
    }
    try {
      final toy = await widget.repository!.setWanted(
        toyId: item.id,
        active: !_wanted,
      );
      _replaceToy(toy);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiMessage(error))));
      }
    }
  }

  Future<void> _setOwned() async {
    if (!_requireInteractionAuth()) return;
    if (!_hasServer) {
      setState(() => _owned = !_owned);
      return;
    }
    try {
      final toy = await widget.repository!.setOwned(
        toyId: item.id,
        active: !_owned,
      );
      _replaceToy(toy);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiMessage(error))));
      }
    }
  }

  Future<void> _toggleSort() async {
    if (!_hasServer) {
      setState(() => _sortByWeight = !_sortByWeight);
      return;
    }
    setState(() => _sortByWeight = !_sortByWeight);
    await _loadRemoteDetail();
  }

  Future<void> _openRatingDialog() async {
    if (!_requireInteractionAuth()) return;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingApiMessage(error, fallback: '评分保存失败')),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment(String value) async {
    if (value.trim().isEmpty) return;
    if (!_requireInteractionAuth()) return;
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
        parentId: _replyTarget?.id,
        replyToUserId: _replyTarget?.authorId,
      );
      if (!mounted) return;
      final detail = _remoteDetail;
      if (detail != null) {
        setState(() {
          _remoteDetail = RankingToyDetail(
            toy: detail.toy,
            comments: [comment, ...detail.comments],
            commentSort: detail.commentSort,
          );
        });
      }
      _commentController.clear();
      setState(() => _replyTarget = null);
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('评论已提交')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingApiMessage(error, fallback: '评论提交失败')),
          ),
        );
      }
    }
  }

  Future<void> _toggleServerCommentLike(RankingToyComment comment) async {
    if (!_requireInteractionAuth()) return;
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
                ? RankingToyComment(
                    id: item.id,
                    authorId: item.authorId,
                    username: item.username,
                    nickname: item.nickname,
                    level: item.level,
                    content: item.content,
                    likeCount: nextCount,
                    isLiked: nextLiked,
                    createdAt: item.createdAt,
                    rootId: item.rootId,
                    parentId: item.parentId,
                    replyToUserId: item.replyToUserId,
                    replyCount: item.replyCount,
                  )
                : item,
          )
          .toList();
      setState(() {
        _remoteDetail = RankingToyDetail(
          toy: _remoteDetail!.toy,
          comments: comments,
          commentSort: _remoteDetail!.commentSort,
        );
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userFacingApiMessage(error))));
      }
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
                onShare: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('分享链接已复制'))),
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
                            child: _DetailRatingCard(item: displayItem),
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
                        _ReviewSection(
                          sortByWeight: _sortByWeight,
                          comments: _serverComments,
                          onToggleSort: _toggleSort,
                          onLike: _toggleServerCommentLike,
                          onReply: (comment) =>
                              setState(() => _replyTarget = comment),
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
              replyTarget: _replyTarget,
              onCancelReply: () => setState(() => _replyTarget = null),
              onSubmitted: _submitComment,
            ),
          ),
        ],
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
            child: Image.asset(item.asset, fit: BoxFit.contain),
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
  const _DetailRatingCard({required this.item});

  final RankingItem item;

  @override
  Widget build(BuildContext context) => Container(
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'LV2以上权重加成',
                    style: TextStyle(color: Color(0xFFAAB4C3), fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              for (final entry in const [
                (5, 1.0),
                (4, 0.0),
                (3, 0.18),
                (2, 0.0),
                (1, 0.0),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: _RatingBar(level: entry.$1, value: entry.$2),
                ),
            ],
          ),
        ),
      ],
    ),
  );
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
    this.onLike,
    this.onReply,
  });

  final bool sortByWeight;
  final VoidCallback onToggleSort;
  final List<RankingToyComment>? comments;
  final ValueChanged<RankingToyComment>? onLike;
  final ValueChanged<RankingToyComment>? onReply;

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
        if (comments == null) ...[
          const _ReviewCard(
            user: '菜菜M',
            likes: '8',
            content: 'A酱的慢玩断折作，比琉璃子好比琉璃子贵就是没有琉璃子陪伴的回忆而已（悲…）',
            reply:
                '杂鱼萌萌(538793014)：大佬你好，这张图在店铺里对应的是二代款［普通版］，还有另一张是二代［经典版］，但是是另一张图，应该是哪个大佬',
            replyDate: '07-29',
            avatarColor: Color(0xFFFFE7B6),
          ),
          const _ReviewCard(
            user: '杂鱼萌萌',
            likes: '3',
            content: '这个盒子的好用一点，比较软，锻炼和练射时长选这个版本就行了。礼盒版是周边多，配送点东西，但是胶体是一样的。',
            reply: null,
            replyDate: null,
            avatarColor: Color(0xFFE3EEFF),
          ),
        ] else if (comments!.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              '还没有评价，来留下第一条吧',
              style: TextStyle(color: Color(0xFF8A96A9)),
            ),
          )
        else
          ..._buildServerCards(comments!),
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
    this.replies = const [],
    this.onReply,
    this.onReplyTo,
  }) : liked = false,
       onLike = null;

  _ReviewCard.server({
    required RankingToyComment comment,
    required this.onLike,
    this.replies = const [],
    this.onReply,
    this.onReplyTo,
  }) : user = comment.nickname.isEmpty ? comment.username : comment.nickname,
       likes = '${comment.likeCount}',
       content = comment.content,
       reply = null,
       replyDate = null,
       avatarColor = const Color(0xFFE3EEFF),
       liked = comment.isLiked;

  final String user;
  final String likes;
  final String content;
  final String? reply;
  final String? replyDate;
  final Color avatarColor;
  final bool liked;
  final VoidCallback? onLike;
  final List<RankingToyComment> replies;
  final VoidCallback? onReply;
  final ValueChanged<RankingToyComment>? onReplyTo;

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
          child: const Icon(
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
                    child: const Text(
                      'LV3',
                      style: TextStyle(
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
                children: List.generate(
                  5,
                  (index) => const Padding(
                    padding: EdgeInsets.only(right: 2),
                    child: Icon(
                      Icons.favorite,
                      size: 13,
                      color: Color(0xFFF76591),
                    ),
                  ),
                ),
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
              if (replies.isNotEmpty)
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 4),
                    title: Text(
                      '查看 ${replies.length} 条回复',
                      style: const TextStyle(
                        color: Color(0xFF3C70B7),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    children: replies.map((replyItem) {
                      final name = replyItem.nickname.isEmpty
                          ? replyItem.username
                          : replyItem.nickname;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 10),
                        title: Text(
                          '$name：${replyItem.content}',
                          style: const TextStyle(
                            color: Color(0xFF3C70B7),
                            fontSize: 12,
                            height: 1.55,
                          ),
                        ),
                        subtitle: Text(
                          relativeTimeLabel(replyItem.createdAt),
                          style: const TextStyle(
                            color: Color(0xFF9AA5B7),
                            fontSize: 10,
                          ),
                        ),
                        onTap: onReplyTo == null
                            ? null
                            : () => onReplyTo!(replyItem),
                      );
                    }).toList(),
                  ),
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
    this.replyTarget,
    this.onCancelReply,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String reviewCount;
  final String wantCount;
  final RankingToyComment? replyTarget;
  final VoidCallback? onCancelReply;
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
                  hintText: replyTarget == null
                      ? '来，说点什么吧!'
                      : '回复 ${replyTarget!.nickname.isEmpty ? replyTarget!.username : replyTarget!.nickname}…',
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
            if (replyTarget != null && onCancelReply != null)
              IconButton(
                tooltip: '取消回复',
                onPressed: onCancelReply,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: const Color(0xFF8A96A9),
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
              child: Image.asset(
                item.asset,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
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
