import 'package:flutter/material.dart';

import '../data/api/platform_repository.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';

enum _NotificationFilter { all, reply, like, system }

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.repository,
    required this.onOpenPostId,
  });

  final PlatformRepository repository;
  final ValueChanged<String> onOpenPostId;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<ForumNotification> items = [];
  final ScrollController scrollController = ScrollController();
  String? nextCursor;
  bool hasMore = true;
  bool loading = false;
  bool loadingMore = false;
  String? errorMessage;
  _NotificationFilter filter = _NotificationFilter.all;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_maybeLoadMore);
    load();
    widget.repository.markAllNotificationsRead();
  }

  @override
  void dispose() {
    scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (scrollController.position.extentAfter < 220) loadMore();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final page = await widget.repository.listNotifications();
      if (!mounted) return;
      setState(() {
        items
          ..clear()
          ..addAll(page.items);
        nextCursor = page.nextCursor;
        hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted) setState(() => errorMessage = '消息加载失败，请重试');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore || nextCursor == null) return;
    setState(() => loadingMore = true);
    try {
      final page = await widget.repository.listNotifications(cursor: nextCursor);
      if (!mounted) return;
      setState(() {
        items.addAll(page.items);
        nextCursor = page.nextCursor;
        hasMore = page.hasMore;
      });
    } catch (_) {
      // 允许滚动到底部后再次触发。
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  List<ForumNotification> get _visible => items.where((item) {
    switch (filter) {
      case _NotificationFilter.all:
        return true;
      case _NotificationFilter.reply:
        return item.type == 'comment.created' ||
            item.type == 'comment.replied';
      case _NotificationFilter.like:
        return item.type == 'post.liked' ||
            item.type == 'user.followed' ||
            item.type.contains('bookmark');
      case _NotificationFilter.system:
        return item.type != 'comment.created' &&
            item.type != 'comment.replied' &&
            item.type != 'post.liked' &&
            item.type != 'user.followed' &&
            !item.type.contains('bookmark');
    }
  }).toList();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('消息', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        if (items.isNotEmpty)
          TextButton(
            onPressed: () async {
              await widget.repository.markAllNotificationsRead();
              if (!mounted) return;
              setState(() {
                for (final item in items) {
                  item.isRead = true;
                }
              });
            },
            child: const Text('全部已读'),
          ),
      ],
    ),
    body: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: _NotificationFilter.values.map((value) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(switch (value) {
                    _NotificationFilter.all => '全部',
                    _NotificationFilter.reply => '回复',
                    _NotificationFilter.like => '赞与收藏',
                    _NotificationFilter.system => '系统',
                  }),
                  selected: value == filter,
                  onSelected: (_) => setState(() => filter = value),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(child: _body()),
      ],
    ),
  );

  Widget _body() {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('消息加载失败', style: TextStyle(color: AppTheme.textSecondary)),
            TextButton(onPressed: load, child: const Text('重试')),
          ],
        ),
      );
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          items.isEmpty ? '暂时没有新消息' : '该分类暂无消息',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(AppTheme.pagePadding),
      itemCount: visible.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == visible.length) {
          return loadingMore
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const SizedBox(height: 8);
        }
        final item = visible[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 5),
          leading: CircleAvatar(
            backgroundColor: AppTheme.surfaceBlue,
            child: Icon(_icon(item.type), color: AppTheme.primary, size: 20),
          ),
          title: Text(
            _title(item),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            relativeTimeLabel(item.createdAt),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          trailing: item.isRead
              ? null
              : const CircleAvatar(radius: 4, backgroundColor: AppTheme.pink),
          onTap: () {
            widget.repository.markNotificationRead(item.id);
            setState(() => item.isRead = true);
            if (item.targetType == 'post') {
              widget.onOpenPostId(item.targetId);
            }
          },
        );
      },
    );
  }

  IconData _icon(String type) => type.contains('like')
      ? Icons.favorite_rounded
      : type.contains('follow')
      ? Icons.person_add_alt_1_rounded
      : type.contains('comment') || type.contains('reply')
      ? Icons.chat_bubble_rounded
      : Icons.campaign_rounded;

  String _title(ForumNotification item) => switch (item.type) {
    'post.liked' => '${item.actorName} 赞了你的帖子',
    'comment.created' ||
    'comment.replied' => '${item.actorName} 回复了你',
    'user.followed' => '${item.actorName} 关注了你',
    _ => '你有一条新通知',
  };
}