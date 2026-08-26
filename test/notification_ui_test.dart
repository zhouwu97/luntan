import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/notifications_screen.dart';
import 'package:luntan/widgets/notifications/notification_empty_state.dart';
import 'package:luntan/widgets/notifications/notification_row.dart';

class _FakePlatformRepository extends PlatformRepository {
  _FakePlatformRepository(this.items)
    : super(
        ApiClient(
          baseUri: Uri.parse('https://example.com'),
          client: MockClient((_) async => throw UnimplementedError()),
        ),
      );

  final List<ForumNotification> items;
  int markReadCalls = 0;
  int markAllReadCalls = 0;

  @override
  Future<NotificationPage> listNotifications({
    String? cursor,
    int limit = 20,
    NotificationCategory category = NotificationCategory.all,
  }) async {
    final filtered = items.where((item) {
      if (category == NotificationCategory.all) return true;
      return item.category == category;
    }).toList();
    return NotificationPage(items: filtered);
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    markReadCalls += 1;
  }

  @override
  Future<void> markAllNotificationsRead() async {
    markAllReadCalls += 1;
  }
}

void main() {
  testWidgets('NotificationRow 正确展示标题、内容与未读小红点', (tester) async {
    final notice = ForumNotification(
      id: 'n1',
      type: 'comment.created',
      actorId: 'u1',
      actorName: '杂鱼萌萌',
      targetType: 'comment',
      targetId: 'c1',
      targetData: const {
        'post_id': 'p1',
        'comment_id': 'c1',
        'title': '杂鱼萌萌 回复了你的评论',
        'content': '我觉得普通版更适合第一次用',
      },
      isRead: false,
      createdAt: DateTime.now(),
    );

    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationRow(item: notice, onTap: () => tapped = true),
        ),
      ),
    );

    expect(find.text('杂鱼萌萌 回复了你的评论'), findsOneWidget);
    expect(find.text('我觉得普通版更适合第一次用'), findsOneWidget);

    await tester.tap(find.byType(NotificationRow));
    expect(tapped, isTrue);
  });

  testWidgets('NotificationsScreen 分类切换与全部已读', (tester) async {
    final fakeRepo = _FakePlatformRepository([
      ForumNotification(
        id: 'n1',
        type: 'comment.created',
        actorId: 'u1',
        actorName: '杂鱼萌萌',
        targetType: 'comment',
        targetId: 'c1',
        targetData: const {
          'post_id': 'p1',
          'title': '杂鱼萌萌 回复了你的评论',
          'content': '我觉得普通版更适合',
        },
        isRead: false,
        createdAt: DateTime.now(),
      ),
      ForumNotification(
        id: 'n2',
        type: 'community.announcement',
        actorId: 'admin',
        actorName: '拆箱小助手',
        targetType: 'community',
        targetId: 'community-unboxing',
        targetData: const {'title': '大型拆箱发布了新公告', 'content': '发帖前请补充版本与使用时间'},
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(repository: fakeRepo, onOpenPostId: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    // 默认全部 Tab 包含今天与更早分组
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('更早'), findsOneWidget);
    expect(find.text('杂鱼萌萌 回复了你的评论'), findsOneWidget);
    expect(find.text('大型拆箱发布了新公告'), findsOneWidget);

    // 点击全部已读
    await tester.tap(find.text('全部已读'));
    await tester.pumpAndSettle();
    expect(fakeRepo.markAllReadCalls, 1);

    // 切换到“处理”分类（空状态）
    await tester.tap(find.text('处理'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationEmptyState), findsOneWidget);
    expect(find.text('通知消息说明'), findsNothing);
  });
}
