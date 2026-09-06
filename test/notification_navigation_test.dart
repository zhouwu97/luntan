import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/notifications_screen.dart';

class _FakePlatformRepository extends PlatformRepository {
  _FakePlatformRepository(this.items)
    : super(
        ApiClient(
          baseUri: Uri.parse('https://example.com'),
          client: MockClient((_) async => throw UnimplementedError()),
        ),
      );

  final List<ForumNotification> items;

  @override
  Future<NotificationPage> listNotifications({
    String? cursor,
    int limit = 20,
    NotificationCategory category = NotificationCategory.all,
  }) async {
    return NotificationPage(items: items);
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {}
}

void main() {
  for (final type in ['store.order.reviewed', 'store.order.shipped', 'store.order.refund']) {
    testWidgets('商城通知 $type 打开订单，优先于系统通知详情', (tester) async {
      String? orderId;
      var systemOpened = false;
      final item = ForumNotification(id: 'store-note', type: type, actorId: 'admin', actorName: '管理员', targetType: 'store_order', targetId: 'order-42', targetData: const {'title': '商城通知测试'}, isRead: true, createdAt: DateTime.now());
      await tester.pumpWidget(MaterialApp(home: NotificationsScreen(
        repository: _FakePlatformRepository([item]), onOpenPostId: (_) {},
        onOpenStoreOrder: (id) => orderId = id,
        onOpenNotification: (_) => systemOpened = true,
        onOpenSystem: () => systemOpened = true,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('商城通知测试'));
      expect(orderId, 'order-42');
      expect(systemOpened, isFalse);
    });
  }
  test('回复通知优先定位新回复，旧 payload 仍定位原楼层', () {
    for (final hasReply in [true, false]) {
      String? focus;
      NotificationTargetRouter.open(
        notification: ForumNotification(id: 'reply-note', type: 'reply', actorId: 'a', actorName: 'a', targetType: 'post', targetId: 'post-1', targetData: {'comment_id': 'root-1', if (hasReply) 'reply_id': 'reply-2'}, isRead: true, createdAt: DateTime.now()),
        onOpenPost: (id, comment) { expect(id, 'post-1'); focus = comment; },
      );
      expect(focus, hasReply ? 'reply-2' : 'root-1');
    }
  });

  testWidgets('点击评论通知正确传递 postId 与 commentId', (tester) async {
    String? capturedPostId;
    String? capturedCommentId;

    final fakeRepo = _FakePlatformRepository([
      ForumNotification(
        id: 'n1',
        type: 'comment.replied',
        actorId: 'u1',
        actorName: '杂鱼萌萌',
        targetType: 'comment',
        targetId: 'reply-123',
        targetData: const {
          'post_id': 'post-abc',
          'comment_id': 'reply-123',
          'title': '杂鱼萌萌 回复了你的评论',
          'content': '“我也用普通版”',
        },
        isRead: false,
        createdAt: DateTime.now(),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: fakeRepo,
          onOpenPostId: (id) => capturedPostId = id,
          onOpenPost: (postId, commentId) {
            capturedPostId = postId;
            capturedCommentId = commentId;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('杂鱼萌萌 回复了你的评论'));
    await tester.pumpAndSettle();

    expect(capturedPostId, 'post-abc');
    expect(capturedCommentId, 'reply-123');
  });

  testWidgets('点击板块通知正确触发 onOpenCommunityId', (tester) async {
    String? capturedCommunityId;

    final fakeRepo = _FakePlatformRepository([
      ForumNotification(
        id: 'n2',
        type: 'community.announcement',
        actorId: 'u2',
        actorName: '拆箱管理员',
        targetType: 'community',
        targetId: 'community-unboxing',
        targetData: const {'title': '大型拆箱发布了新公告', 'content': '公告内容'},
        isRead: false,
        createdAt: DateTime.now(),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          repository: fakeRepo,
          onOpenPostId: (_) {},
          onOpenCommunityId: (id) => capturedCommunityId = id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('大型拆箱发布了新公告'));
    await tester.pumpAndSettle();

    expect(capturedCommunityId, 'community-unboxing');
  });
}
