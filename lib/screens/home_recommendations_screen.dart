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
            title: const Text('移出首页推荐？'),
            content: Text('“${item.title}”将不再出现在人工推荐流中。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
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
    appBar: AppBar(
      title: const Text('首页推荐'),
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
                '暂无首页推荐\n可在帖子菜单中加入推荐',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, height: 1.6),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: items.length,
        onReorderItem: _reorder,
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            key: ValueKey(item.postId),
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle, color: AppTheme.primary),
              ),
              title: Text(
                '${index + 1}. ${item.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  [
                    if (item.communityName.isNotEmpty) item.communityName,
                    if (item.authorName.isNotEmpty) item.authorName,
                    _dateLabel(item.recommendedAt),
                    if (item.expiresAt != null)
                      '有效期至 ${_dateLabel(item.expiresAt!)}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: '移出推荐',
                onPressed: saving ? null : () => _remove(item),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              onTap: widget.onOpenPostId == null
                  ? null
                  : () => widget.onOpenPostId!(item.postId),
            ),
          );
        },
      ),
    );
  }

  String _dateLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
