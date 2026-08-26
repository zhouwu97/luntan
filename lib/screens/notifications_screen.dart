import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../domain/models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../widgets/notifications/notification_empty_state.dart';
import '../widgets/notifications/notification_row.dart';
import '../widgets/notifications/notification_skeleton.dart';

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
    this.onOpenNotification,
    this.onOpenModerationActionId,
    this.onOpenAppealId,
  });

  final PlatformRepository repository;
  final ValueChanged<String> onOpenPostId;
  final void Function(String postId, String? commentId)? onOpenPost;
  final ValueChanged<String>? onOpenUserId;
  final ValueChanged<String>? onOpenCommunityId;
  final VoidCallback? onOpenSystem;
  final ValueChanged<ForumNotification>? onOpenNotification;
  final ValueChanged<String>? onOpenModerationActionId;
  final ValueChanged<String>? onOpenAppealId;

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
  String? loadMoreError;
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
      loadMoreError = null;
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
        loadMoreError = null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => loadMoreError = '加载更多失败，点击重试');
      }
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
    if (scrollController.hasClients) {
      scrollController.animateTo(
        0,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      await widget.repository.markAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        for (final item in items) {
          item.isRead = true;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全部通知已标为已读')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingApiMessage(error))),
      );
    }
  }

  void _handleNotificationTap(ForumNotification item) {
    if (!item.isRead) {
      setState(() => item.isRead = true);
      unawaited(_markNotificationRead(item));
    }
    if (item.type == 'system' ||
        item.type == 'announcement' ||
        item.type.startsWith('community.')) {
      if (widget.onOpenNotification != null) {
        widget.onOpenNotification!(item);
        return;
      }
    }
    if (item.isModeration && item.type == 'moderation.action') {
      final actionId = item.moderationActionId ?? item.targetId;
      if (widget.onOpenModerationActionId != null && actionId.isNotEmpty) {
        widget.onOpenModerationActionId!(actionId);
        return;
      }
    }
    if (item.type == 'appeal.result') {
      final appealId = item.targetData['appeal_id'];
      if (widget.onOpenAppealId != null &&
          appealId is String &&
          appealId.isNotEmpty) {
        widget.onOpenAppealId!(appealId);
        return;
      }
    }
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
  }

  Future<void> _markNotificationRead(ForumNotification item) async {
    try {
      await widget.repository.markNotificationRead(item.id);
    } catch (_) {
      if (!mounted || !items.contains(item)) return;
      setState(() => item.isRead = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            '通知',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: _markAllRead,
              child: const Text(
                '全部已读',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 分类选择轻量 Segment
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
            child: _NoticeKindTabs(
              selected: filter,
              onChanged: _selectFilter,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (loading && items.isEmpty) {
      return const NotificationSkeleton(itemCount: 4);
    }
    if (errorMessage != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: load,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return NotificationEmptyState(
        categoryName: _categoryLabel(filter),
        onResetCategory: () => _selectFilter(NotificationCategory.all),
      );
    }

    // 按自然日期分组（今天 / 更早）
    final today = DateTime.now();
    final todayItems = <ForumNotification>[];
    final earlierItems = <ForumNotification>[];

    for (final item in items) {
      final isToday = item.createdAt.year == today.year &&
          item.createdAt.month == today.month &&
          item.createdAt.day == today.day;
      if (isToday) {
        todayItems.add(item);
      } else {
        earlierItems.add(item);
      }
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 24),
      children: [
        if (todayItems.isNotEmpty) ...[
          _buildDayHeader('今天'),
          _buildGroupContainer(
            children: todayItems
                .map((item) => NotificationRow(
                      item: item,
                      onTap: () => _handleNotificationTap(item),
                    ))
                .toList(),
          ),
        ],
        if (earlierItems.isNotEmpty) ...[
          _buildDayHeader('更早'),
          _buildGroupContainer(
            children: earlierItems
                .map((item) => NotificationRow(
                      item: item,
                      onTap: () => _handleNotificationTap(item),
                    ))
                .toList(),
          ),
        ],
        if (loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (loadMoreError != null)
          Center(
            child: TextButton(
              onPressed: loadMore,
              child: Text(
                loadMoreError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDayHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF8A9BAC),
        ),
      ),
    );
  }

  Widget _buildGroupContainer({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppTheme.border),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: children.length,
          separatorBuilder: (context, index) => const Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFFEDF2F6),
          ),
          itemBuilder: (context, index) => children[index],
        ),
      ),
    );
  }

  String _categoryLabel(NotificationCategory category) => switch (category) {
    NotificationCategory.all => '全部',
    NotificationCategory.interaction => '互动',
    NotificationCategory.community => '社区',
    NotificationCategory.moderation => '处理',
    _ => '全部',
  };
}

class _NoticeKindTabs extends StatelessWidget {
  const _NoticeKindTabs({
    required this.selected,
    required this.onChanged,
  });

  final NotificationCategory selected;
  final ValueChanged<NotificationCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = [
      NotificationCategory.all,
      NotificationCategory.interaction,
      NotificationCategory.community,
      NotificationCategory.moderation,
    ];

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: values.map((value) {
          final isSelected = value == selected;
          final label = switch (value) {
            NotificationCategory.all => '全部',
            NotificationCategory.interaction => '互动',
            NotificationCategory.community => '社区',
            NotificationCategory.moderation => '处理',
            _ => '全部',
          };
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.standard,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? const [
                          BoxShadow(
                            color: Color(0x122D4B69),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF2E5F96)
                        : const Color(0xFF6C8093),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 统一的系统/公告通知详情页，避免用户点击通知后只得到一条无上下文的提示。
class NotificationDetailScreen extends StatelessWidget {
  const NotificationDetailScreen({
    super.key,
    required this.repository,
    required this.notification,
    this.onOpenTarget,
  });

  final PlatformRepository repository;
  final ForumNotification notification;
  final VoidCallback? onOpenTarget;

  @override
  Widget build(BuildContext context) {
    final data = notification.targetData;
    final title = _text(data, 'title') ?? _notificationTitle(notification);
    final body =
        _text(data, 'body') ??
        _text(data, 'content') ??
        _text(data, 'message') ??
        _text(data, 'description') ??
        '暂无详细内容';
    return Scaffold(
      appBar: AppBar(title: const Text('通知详情')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.pagePadding),
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '${notification.createdAt.year}-${notification.createdAt.month.toString().padLeft(2, '0')}-${notification.createdAt.day.toString().padLeft(2, '0')} ${notification.createdAt.hour.toString().padLeft(2, '0')}:${notification.createdAt.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(body, style: const TextStyle(height: 1.6)),
            ),
          ),
          if (onOpenTarget != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpenTarget,
              icon: const Icon(Icons.open_in_new),
              label: const Text('查看相关内容'),
            ),
          ],
        ],
      ),
    );
  }

  static String? _text(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }
}

String _notificationTitle(ForumNotification item) => switch (item.type) {
  'announcement' || 'community.announcement' => '社区公告',
  'community.event' || 'event' => '活动通知',
  'community.maintenance' || 'maintenance' => '系统维护通知',
  'moderation.action' => '账号/内容处理通知',
  'appeal.result' => '申诉结果通知',
  _ => '系统通知',
};
