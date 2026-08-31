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
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  '长按并拖动左侧把手调整顺序\n松手后立即保存',
                  style: TextStyle(
                    color: Color(0xFF72879A),
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
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
                  final isFirst = index == 0;
                  return Container(
                    key: ValueKey(item.id),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: isFirst
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
                                [
                                  rankingToyCategoryLabel(item.category),
                                  if (item.merchant.isNotEmpty) item.merchant,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
