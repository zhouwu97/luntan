import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../data/api/ranking_repository.dart';
import '../theme/app_theme.dart';
import 'ranking_toy_submission_screen.dart';

class RankingReorderScreen extends StatefulWidget {
  const RankingReorderScreen({
    super.key,
    required this.rankingRepository,
    required this.platformRepository,
    this.onFeedback,
  });

  final RankingRepository rankingRepository;
  final PlatformRepository platformRepository;
  final ValueChanged<String>? onFeedback;

  @override
  State<RankingReorderScreen> createState() => _RankingReorderScreenState();
}

class _RankingReorderScreenState extends State<RankingReorderScreen> {
  List<RankingToy> items = const [];
  Object? error;
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _feedback(String message) => widget.onFeedback?.call(message);

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.rankingRepository.list();
      if (!mounted) return;
      setState(() {
        items = loaded.items;
        loading = false;
      });
    } catch (cause) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = cause;
      });
    }
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
    final previous = List<RankingToy>.of(items);
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    setState(() => saving = true);
    try {
      await widget.platformRepository.reorderRankingToys(
        items.map((item) => item.id).toList(),
      );
      if (mounted) _feedback('综合热榜名次已保存');
    } catch (cause) {
      if (!mounted) return;
      setState(() {
        items
          ..clear()
          ..addAll(previous);
      });
      if (cause is ApiException && cause.code == 'RANKING_REORDER_STALE') {
        _feedback('榜单有更新，请刷新后重试');
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
    body: _body(),
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
                '榜单暂无玩具',
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '拖动调整综合热榜名次，保存后立即生效',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              itemCount: items.length,
              onReorder: _reorder,
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  key: ValueKey(item.id),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: SizedBox(
                      width: 48,
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(
                              Icons.drag_handle,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    title: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        [
                          rankingToyCategoryLabel(item.category),
                          if (item.merchant.isNotEmpty) item.merchant,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
