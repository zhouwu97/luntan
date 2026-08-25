import 'package:flutter/material.dart';

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
  });

  final int rank;
  final String name;
  final String hot;
  final List<String> tags;
  final String ratings;
  final String score;
  final String asset;
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
  rank: 1,
  name: '黄油小姐 二代',
  hot: '本周热门',
  tags: ['奶香体质', '软糯入门', '果冻包裹'],
  ratings: '热门榜首',
  score: '8.7',
  asset: 'assets/ranking/hero.webp',
);

const _rankingTabs = ['综合热榜', '慢玩入门', '进阶训练', '超高刺激', '榨汁玩具'];

class RankingPage extends StatefulWidget {
  const RankingPage({super.key});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  int _selectedTab = 0;
  int _selectedCategory = 0;

  List<RankingItem> get _items =>
      _selectedTab == 1 ? _slowRankingItems : _mainRankingItems;

  void _openRankingItem(RankingItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RankingItemDetailPage(item: item),
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
                    onTap: () => _openRankingItem(_topRankingItem),
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
  const _TopRankingCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    onTap: onTap,
    label: '第1名 黄油小姐 二代，8.7 分',
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
                          const Text(
                            '黄油小姐 二代',
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
                            children: [
                              '奶香体质',
                              '软糯入门',
                              '果冻包裹',
                            ].map(_TagChip.new).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '8.7',
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

/// 榜单条目详情；静态榜单也要有可用的二级页面，避免卡片只是图片。
class RankingItemDetailPage extends StatelessWidget {
  const RankingItemDetailPage({super.key, required this.item});

  final RankingItem item;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF2F1F6),
    appBar: AppBar(
      title: Text(item.name),
      backgroundColor: const Color(0xFFF2F1F6),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: Tooltip(
        message: '返回',
        child: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 1.45,
            child: Image.asset(item.asset, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF3F4F6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        color: Color(0xFF222222),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${item.score} 分',
                    style: const TextStyle(
                      color: Color(0xFFEA6D93),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: item.tags.map(_TagChip.new).toList(),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Text(
                '${item.hot} · ${item.ratings}',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text(
                '榜单详情',
                style: TextStyle(
                  color: Color(0xFF222222),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '这是榜单展示占位内容，后续可以在这里补充产品介绍、用户评价和相关帖子。',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
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
