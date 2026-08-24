import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';

typedef NotificationPostOpener =
    void Function(String postId, String? commentId);

/// 将通知目标统一转换成页面动作，避免通知页面堆积不可维护的条件分支。
class NotificationTargetRouter {
  const NotificationTargetRouter._();

  static void open({
    required ForumNotification notification,
    required NotificationPostOpener onOpenPost,
    ValueChanged<String>? onOpenUser,
    ValueChanged<String>? onOpenCommunity,
    VoidCallback? onOpenSystem,
  }) {
    final targetData = notification.targetData;
    switch (notification.targetType) {
      case 'post':
        onOpenPost(
          notification.targetId,
          _stringValue(targetData['comment_id']),
        );
      case 'comment':
        final postId = targetData['post_id'];
        if (postId is String && postId.isNotEmpty) {
          onOpenPost(postId, notification.targetId);
        } else {
          onOpenSystem?.call();
        }
      case 'user':
        onOpenUser?.call(notification.targetId);
      case 'community':
        onOpenCommunity?.call(notification.targetId);
      case 'system':
        onOpenSystem?.call();
      default:
        final postId = targetData['post_id'];
        if (postId is String && postId.isNotEmpty) {
          onOpenPost(postId, _stringValue(targetData['comment_id']));
        } else {
          onOpenSystem?.call();
        }
    }
  }

  static String? _stringValue(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.repository,
    required this.onOpenPostId,
    this.onOpenPost,
    this.onOpenUserId,
    this.onOpenCommunityId,
    this.onOpenSystem,
  });

  final PlatformRepository repository;
  final ValueChanged<String> onOpenPostId;
  final void Function(String postId, String? commentId)? onOpenPost;
  final ValueChanged<String>? onOpenUserId;
  final ValueChanged<String>? onOpenCommunityId;
  final VoidCallback? onOpenSystem;

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
  NotificationCategory filter = NotificationCategory.all;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_maybeLoadMore);
    load();
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
    final generation = ++_generation;
    final requestedFilter = filter;
    setState(() {
      loading = true;
      errorMessage = null;
      items.clear();
      nextCursor = null;
      hasMore = true;
    });
    try {
      final page = await widget.repository.listNotifications(
        category: requestedFilter,
      );
      if (!mounted || generation != _generation || filter != requestedFilter) {
        return;
      }
      setState(() {
        items
          ..clear()
          ..addAll(page.items);
        nextCursor = page.nextCursor;
        hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => errorMessage = '消息加载失败，请重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore || nextCursor == null) return;
    final generation = _generation;
    final requestedFilter = filter;
    final requestedCursor = nextCursor;
    setState(() => loadingMore = true);
    try {
      final page = await widget.repository.listNotifications(
        cursor: requestedCursor,
        category: requestedFilter,
      );
      if (!mounted || generation != _generation || filter != requestedFilter) {
        return;
      }
      setState(() {
        items.addAll(page.items);
        nextCursor = page.nextCursor;
        hasMore = page.hasMore;
      });
    } catch (_) {
      // 允许滚动到底部后再次触发。
    } finally {
      if (mounted && generation == _generation) {
        setState(() => loadingMore = false);
      }
    }
  }

  void _selectFilter(NotificationCategory value) {
    if (value == filter) return;
    setState(() => filter = value);
    load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('消息', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        if (items.isNotEmpty)
          TextButton(
            onPressed: () async {
              try {
                await widget.repository.markAllNotificationsRead();
                if (!context.mounted) return;
                setState(() {
                  for (final item in items) {
                    item.isRead = true;
                  }
                });
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(userFacingApiMessage(error))),
                );
              }
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
            children: NotificationCategory.values.map((value) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(switch (value) {
                    NotificationCategory.all => '全部',
                    NotificationCategory.reply => '回复',
                    NotificationCategory.like => '赞与收藏',
                    NotificationCategory.system => '系统',
                  }),
                  selected: value == filter,
                  onSelected: (_) => _selectFilter(value),
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
            const Text(
              '消息加载失败',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            TextButton(onPressed: load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          filter == NotificationCategory.all ? '暂时没有新消息' : '该分类暂无消息',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(AppTheme.pagePadding),
      itemCount: items.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == items.length) {
          return loadingMore
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const SizedBox(height: 8);
        }
        final item = items[index];
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
          onTap: () async {
            if (!item.isRead) {
              setState(() => item.isRead = true);
              try {
                await widget.repository.markNotificationRead(item.id);
              } catch (error) {
                if (!context.mounted) return;
                setState(() => item.isRead = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(userFacingApiMessage(error))),
                );
                return;
              }
            }
            if (!context.mounted) return;
            NotificationTargetRouter.open(
              notification: item,
              onOpenPost: (postId, commentId) {
                if (widget.onOpenPost != null) {
                  widget.onOpenPost!(postId, commentId);
                } else {
                  widget.onOpenPostId(postId);
                }
              },
              onOpenUser: widget.onOpenUserId,
              onOpenCommunity: widget.onOpenCommunityId,
              onOpenSystem: widget.onOpenSystem,
            );
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
    'like' || 'post.liked' => '${item.actorName} 赞了你的帖子',
    'bookmark' || 'post.bookmarked' => '${item.actorName} 收藏了你的帖子',
    'comment.created' ||
    'comment.replied' ||
    'reply' => '${item.actorName} 回复了你',
    'follow' || 'user.followed' => '${item.actorName} 关注了你',
    _ => '你有一条新通知',
  };
}
