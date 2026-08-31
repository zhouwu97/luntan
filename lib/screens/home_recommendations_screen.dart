import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../theme/app_theme.dart';

class HomeRecommendationsScreen extends StatefulWidget {
  const HomeRecommendationsScreen({
    super.key,
    required this.repository,
    required this.onFeedback,
    this.onOpenPostId,
  });

  final PlatformRepository repository;
  final ValueChanged<String> onFeedback;
  final ValueChanged<String>? onOpenPostId;

  @override
  State<HomeRecommendationsScreen> createState() =>
      _HomeRecommendationsScreenState();
}

class _HomeRecommendationsScreenState extends State<HomeRecommendationsScreen> {
  final items = <HomeRecommendation>[];
  Object? error;
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.repository.listHomeRecommendations();
      if (!mounted) return;
      setState(() {
        items
          ..clear()
          ..addAll(loaded);
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
    final previous = List<HomeRecommendation>.of(items);
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    setState(() => saving = true);
    try {
      await widget.repository.reorderHomeRecommendations(
        items.map((item) => item.postId).toList(),
      );
      if (mounted) widget.onFeedback('首页推荐顺序已保存');
    } catch (cause) {
      if (mounted) {
        setState(() {
          items
            ..clear()
            ..addAll(previous);
        });
        widget.onFeedback(userFacingApiMessage(cause, fallback: '推荐顺序保存失败'));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _remove(HomeRecommendation item) async {
    if (saving) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('移出首页推荐？', style: TextStyle(fontWeight: FontWeight.w800)),
            content: Text('“${item.title}”将不再出现在人工推荐流中。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.pink),
                onPressed: () => Navigator.pop(dialogContext, true),
                 child: const Text('移出推荐'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => saving = true);
    try {
      await widget.repository.removeHomeRecommendation(item.postId);
      if (!mounted) return;
      setState(() => items.removeWhere((value) => value.postId == item.postId));
      widget.onFeedback('已移出首页推荐');
    } catch (cause) {
      if (mounted) {
        widget.onFeedback(userFacingApiMessage(cause, fallback: '移出推荐失败'));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(
      title: const Text(
        '首页推荐',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
      ),
      backgroundColor: AppTheme.background,
      elevation: 0,
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
      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
        ),
      );
    }
    if (error != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 36, color: AppTheme.textSecondary),
            const SizedBox(height: 10),
            const Text('加载推荐列表失败', style: TextStyle(color: AppTheme.pink, fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F1FA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.push_pin_outlined, size: 28, color: Color(0xFF6B8299)),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '暂无首页推荐',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF304A65),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '管理员可在帖子详情菜单中将优质内容加入精选',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
        itemCount: items.length,
        // 3.41.8 无 onReorderItem，待 SDK 统一后迁移
        // ignore: deprecated_member_use
        onReorder: _reorder,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            key: ValueKey(item.postId),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
              boxShadow: const [AppTheme.cardShadow],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onOpenPostId == null
                    ? null
                    : () => widget.onOpenPostId!(item.postId),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.softViolet,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.drag_indicator_rounded, color: AppTheme.purple, size: 18),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${index + 1}. ${item.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                if (item.communityName.isNotEmpty) item.communityName,
                                if (item.authorName.isNotEmpty) item.authorName,
                                _dateLabel(item.recommendedAt),
                                if (item.expiresAt != null)
                                  '至 ${_dateLabel(item.expiresAt!)}',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '移出推荐',
                        onPressed: saving ? null : () => _remove(item),
                        icon: const Icon(Icons.remove_circle_outline_rounded, color: Color(0xFF8FA3B8), size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _dateLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
