import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../theme/app_theme.dart';

class RankingReorderScreen extends StatefulWidget {
  const RankingReorderScreen({
    super.key,
    required this.platformRepository,
    this.initialTab = '',
    this.initialCategory = '',
    this.onFeedback,
  });

  final PlatformRepository platformRepository;
  final String initialTab;
  final String initialCategory;
  final ValueChanged<String>? onFeedback;

  @override
  State<RankingReorderScreen> createState() => _RankingReorderScreenState();
}

class _RankingReorderScreenState extends State<RankingReorderScreen> {
  static const _tabs = <_RankingViewOption>[
    _RankingViewOption('综合热榜', ''),
    _RankingViewOption('慢玩入门', 'ENTRY'),
    _RankingViewOption('进阶训练', 'ADVANCED'),
    _RankingViewOption('超高刺激', 'HIGH'),
    _RankingViewOption('榨汁玩具', 'EXTREME'),
  ];
  static const _categories = <_RankingViewOption>[
    _RankingViewOption('全部', ''),
    _RankingViewOption('飞机杯', 'CUP'),
    _RankingViewOption('小型臀模', 'SMALL_MOLD'),
    _RankingViewOption('大型臀模', 'LARGE_MOLD'),
    _RankingViewOption('半身腿模', 'HALF_BODY'),
    _RankingViewOption('润滑油', 'LUBE'),
  ];

  List<RankingViewOrderItem> items = const [];
  Object? error;
  bool loading = true;
  bool saving = false;
  int _version = 0;
  int _loadRequest = 0;
  late String _tab;
  late String _category;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _category = _tab.isEmpty
        ? widget.initialCategory
        : widget.initialCategory.isEmpty
        ? 'CUP'
        : widget.initialCategory;
    _load();
  }

  void _feedback(String message) {
    widget.onFeedback?.call(message);
    if (widget.onFeedback == null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String get _viewLabel {
    final tabLabel = _tabs.firstWhere((item) => item.key == _tab).label;
    if (_category.isEmpty) return tabLabel;
    final categoryLabel = _categories
        .firstWhere((item) => item.key == _category)
        .label;
    return '$tabLabel · $categoryLabel';
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    final tab = _tab;
    final category = _category;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.platformRepository.getRankingViewOrder(
        tab: tab,
        category: category,
      );
      if (!mounted || request != _loadRequest) return;
      setState(() {
        items = loaded.items;
        _version = loaded.version;
        loading = false;
      });
    } catch (cause) {
      if (!mounted || request != _loadRequest) return;
      setState(() {
        loading = false;
        error = cause;
      });
    }
  }

  void _selectTab(String tab) {
    if (saving || tab == _tab) return;
    setState(() {
      _tab = tab;
      if (_tab.isNotEmpty && _category.isEmpty) _category = 'CUP';
    });
    _load();
  }

  void _selectCategory(String category) {
    if (saving || category == _category) return;
    if (_tab.isNotEmpty && category.isEmpty) return;
    setState(() => _category = category);
    _load();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (saving) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= items.length ||
        newIndex < 0 ||
        newIndex >= items.length) {
      return;
    }

    final previous = List<RankingViewOrderItem>.of(items);
    final next = List<RankingViewOrderItem>.of(items);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    final tab = _tab;
    final category = _category;
    setState(() {
      items = next;
      saving = true;
      error = null;
    });
    try {
      final version = await widget.platformRepository.saveRankingViewOrder(
        tab: tab,
        category: category,
        orderedToyIds: next.map((item) => item.toyId).toList(),
        version: _version,
      );
      if (!mounted) return;
      setState(() => _version = version);
      _feedback('$_viewLabel 名次已保存');
    } catch (cause) {
      if (!mounted) return;
      setState(() => items = previous);
      if (cause is ApiException && cause.code == 'RANKING_VIEW_ORDER_STALE') {
        _feedback('当前榜单有更新，请刷新后重试');
        await _load();
      } else {
        _feedback('名次保存失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('调整榜单名次'),
      actions: [
        if (saving)
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    ),
    body: Column(
      children: [
        _ViewTabs(options: _tabs, selectedKey: _tab, onSelected: _selectTab),
        _ViewTabs(
          options: _categories,
          selectedKey: _category,
          onSelected: _selectCategory,
          disabledKey: _tab.isEmpty ? null : '',
          compact: true,
        ),
        Expanded(child: _body()),
      ],
    ),
  );

  Widget _body() {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && items.isEmpty) {
      return Center(
        child: TextButton(onPressed: _load, child: const Text('加载失败，重试')),
      );
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 180),
            Center(
              child: Text(
                '当前视图暂无玩具',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    '当前仅调整「$_viewLabel」\n长按并拖动左侧把手，松手后立即保存',
                    style: const TextStyle(
                      color: Color(0xFF72879A),
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  saving ? '保存中…' : '${items.length} 项',
                  style: TextStyle(
                    color: saving
                        ? const Color(0xFF2B6DBA)
                        : const Color(0xFF7A8B9B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEAF0F6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ReorderableListView.builder(
                itemCount: items.length,
                // ignore: deprecated_member_use
                onReorder: _reorder,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Container(
                    key: ValueKey(item.toyId),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: index == 0
                          ? null
                          : const Border(
                              top: BorderSide(
                                color: Color(0xFFEDF2F6),
                                width: 1,
                              ),
                            ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: const SizedBox(
                            width: 28,
                            height: 38,
                            child: Center(
                              child: Icon(
                                Icons.drag_handle,
                                color: Color(0xFF91A3B5),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 24,
                          child: Text(
                            (index + 1).toString().padLeft(2, '0'),
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF203244),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '源榜单名次 ${item.sourceRank}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF7A8FA2),
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.options,
    required this.selectedKey,
    required this.onSelected,
    this.disabledKey,
    this.compact = false,
  });

  final List<_RankingViewOption> options;
  final String selectedKey;
  final ValueChanged<String> onSelected;
  final String? disabledKey;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    height: compact ? 42 : 46,
    color: compact ? const Color(0xFFF8FAFC) : Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(option.label),
                selected: selectedKey == option.key,
                onSelected: option.key == disabledKey
                    ? null
                    : (_) => onSelected(option.key),
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(
                  fontSize: compact ? 11 : 13,
                  fontWeight: selectedKey == option.key
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _RankingViewOption {
  const _RankingViewOption(this.label, this.key);

  final String label;
  final String key;
}
