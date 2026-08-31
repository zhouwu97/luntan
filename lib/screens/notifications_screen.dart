import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
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
    ValueChanged<String>? onFeedback,
  }) {
    final targetData = notification.targetData;
    try {
      switch (notification.targetType) {
        case 'post':
          if (notification.targetId.isNotEmpty) {
            onOpenPost(
              notification.targetId,
              _stringValue(targetData['comment_id']),
            );
          } else {
            onFeedback?.call('关联的帖子已不存在');
          }
        case 'comment':
          final postId = targetData['post_id'];
          if (postId is String && postId.isNotEmpty) {
            onOpenPost(postId, notification.targetId);
          } else {
            onOpenSystem?.call();
          }
        case 'user':
          if (notification.targetId.isNotEmpty) {
            onOpenUser?.call(notification.targetId);
          }
        case 'community':
          if (notification.targetId.isNotEmpty) {
            onOpenCommunity?.call(notification.targetId);
          }
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
    } catch (_) {
      onFeedback?.call('目标内容已被移除或无权限查看');
    }
  }

  static String? _stringValue(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;
}

class _TabState {
  final List<ForumNotification> items = [];
  String? nextCursor;
  bool hasMore = true;
  bool loaded = false;
  bool loading = false;
  String? errorMessage;
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
  final ScrollController scrollController = ScrollController();
  NotificationCategory filter = NotificationCategory.all;
  bool loadingMore = false;
  String? loadMoreError;
  int _generation = 0;

  final Map<NotificationCategory, _TabState> _tabStates = {
    NotificationCategory.all: _TabState(),
    NotificationCategory.interaction: _TabState(),
    NotificationCategory.community: _TabState(),
    NotificationCategory.moderation: _TabState(),
  };

  _TabState get _currentState => _tabStates[filter] ?? _tabStates[NotificationCategory.all]!;
  List<ForumNotification> get items => _currentState.items;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_maybeLoadMore);
    _loadTab(filter);
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

  Future<void> _loadTab(NotificationCategory category, {bool forceRefresh = false}) async {
    final tabState = _tabStates[category] ?? _tabStates[NotificationCategory.all]!;
    if (tabState.loading) return;
    if (tabState.loaded && !forceRefresh) {
      if (mounted) setState(() {});
      return;
    }

    final generation = ++_generation;
    setState(() {
      tabState.loading = true;
      tabState.errorMessage = null;
      loadMoreError = null;
      if (forceRefresh) {
        tabState.items.clear();
        tabState.nextCursor = null;
        tabState.hasMore = true;
      }
    });

    try {
      final page = await widget.repository.listNotifications(category: category);
      if (!mounted || generation != _generation) return;
      setState(() {
        tabState.items
          ..clear()
          ..addAll(page.items);
        tabState.nextCursor = page.nextCursor;
        tabState.hasMore = page.hasMore;
        tabState.loaded = true;
        tabState.loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          tabState.errorMessage = '通知加载失败，请重试';
          tabState.loading = false;
        });
      }
    }
  }

  Future<void> load() => _loadTab(filter, forceRefresh: true);

  Future<void> loadMore() async {
    final tabState = _currentState;
    if (tabState.loading || loadingMore || !tabState.hasMore || tabState.nextCursor == null) {
      return;
    }
    final generation = _generation;
    final requestedCategory = filter;
    final requestedCursor = tabState.nextCursor;

    setState(() => loadingMore = true);
    try {
      final page = await widget.repository.listNotifications(
        cursor: requestedCursor,
        category: requestedCategory,
      );
      if (!mounted || generation != _generation || filter != requestedCategory) {
        return;
      }
      setState(() {
        tabState.items.addAll(page.items);
        tabState.nextCursor = page.nextCursor;
        tabState.hasMore = page.hasMore;
        loadMoreError = null;
        loadingMore = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          loadMoreError = '加载更多失败，点击重试';
          loadingMore = false;
        });
      }
    }
  }

  void _selectFilter(NotificationCategory value) {
    if (value == filter) return;
    setState(() => filter = value);
    _loadTab(value);
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
        for (final state in _tabStates.values) {
          for (final item in state.items) {
            item.isRead = true;
          }
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('全部通知已标为已读')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingApiMessage(error))));
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
      onFeedback: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      },
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
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            '通知',
            style: TextStyle(
              fontSize: 19,
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
            child: _NoticeKindTabs(selected: filter, onChanged: _selectFilter),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final state = _currentState;
    if (state.loading && state.items.isEmpty) {
      return const NotificationSkeleton(itemCount: 4);
    }
    if (state.errorMessage != null && state.items.isEmpty) {
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
              state.errorMessage!,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: load,
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (state.items.isEmpty) {
      return NotificationEmptyState(
        categoryName: _categoryLabel(filter),
        onResetCategory: () => _selectFilter(NotificationCategory.all),
      );
    }

    // 按自然日期分组（今天 / 更早）
    final today = DateTime.now();
    final todayItems = <ForumNotification>[];
    final earlierItems = <ForumNotification>[];

    for (final item in state.items) {
      final isToday =
          item.createdAt.year == today.year &&
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
                .map(
                  (item) => NotificationRow(
                    item: item,
                    onTap: () => _handleNotificationTap(item),
                  ),
                )
                .toList(),
          ),
        ],
        if (earlierItems.isNotEmpty) ...[
          _buildDayHeader('更早'),
          _buildGroupContainer(
            children: earlierItems
                .map(
                  (item) => NotificationRow(
                    item: item,
                    onTap: () => _handleNotificationTap(item),
                  ),
                )
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [AppTheme.cardShadow],
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: children.length,
          separatorBuilder: (context, index) =>
              const Divider(height: 1, thickness: 1, color: Color(0xFFEDF2F6)),
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
  const _NoticeKindTabs({required this.selected, required this.onChanged});

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
        borderRadius: BorderRadius.circular(13),
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
                  borderRadius: BorderRadius.circular(10),
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
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF356FC4)
                        : const Color(0xFF71869B),
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
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('通知详情', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            '${notification.createdAt.year}-${notification.createdAt.month.toString().padLeft(2, '0')}-${notification.createdAt.day.toString().padLeft(2, '0')} ${notification.createdAt.hour.toString().padLeft(2, '0')}:${notification.createdAt.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
              boxShadow: const [AppTheme.cardShadow],
            ),
            padding: const EdgeInsets.all(18),
            child: Text(body, style: const TextStyle(height: 1.65, fontSize: 13.5, color: AppTheme.textPrimary)),
          ),
          if (onOpenTarget != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onOpenTarget,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('查看相关内容'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
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
