import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/notifications_screen.dart';
import 'package:luntan/widgets/notifications/notification_row.dart';

class _RecordingPlatformRepository extends PlatformRepository {
  _RecordingPlatformRepository()
    : super(
        ApiClient(
          baseUri: Uri.parse('https://example.com'),
          client: MockClient((_) async => throw UnimplementedError()),
        ),
      );

  final List<NotificationCategory> categories = [];
  int markAllCalls = 0;

  @override
  Future<NotificationPage> listNotifications({
    String? cursor,
    int limit = 20,
    NotificationCategory category = NotificationCategory.all,
  }) async {
    categories.add(category);
    return const NotificationPage(items: []);
  }

  @override
  Future<void> markAllNotificationsRead() async {
    markAllCalls += 1;
  }
}

void main() {
  testWidgets('首屏请求跨分类完成后仍可返回原分类', (tester) async {
    final repo = _DeferredRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(repository: repo, onOpenPostId: (_) {}),
      ),
    );
    await tester.tap(find.text('互动'));
    await tester.pump();
    repo.requests['all:first']!.complete(
      NotificationPage(items: [_notice('全部消息')]),
    );
    repo.requests['interaction:first']!.complete(
      NotificationPage(items: [_notice('互动消息')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('互动消息 赞了你的帖子'), findsOneWidget);
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('全部消息 赞了你的帖子'), findsOneWidget);
  });

  testWidgets('旧分类分页完成不污染新分类且分页锁会释放', (tester) async {
    final repo = _DeferredRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(repository: repo, onOpenPostId: (_) {}),
      ),
    );
    repo.requests['all:first']!.complete(
      NotificationPage(
        items: [_notice('全部一')],
        nextCursor: 'next',
        hasMore: true,
      ),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(NotificationsScreen));
    final Future<void> oldPage = state.loadMore();
    await tester.pump();
    await tester.tap(find.text('互动'));
    await tester.pump();
    repo.requests['interaction:first']!.complete(
      NotificationPage(
        items: [_notice('互动一')],
        nextCursor: 'next',
        hasMore: true,
      ),
    );
    repo.requests['all:next']!.complete(
      NotificationPage(items: [_notice('全部二')]),
    );
    await oldPage;
    await tester.pumpAndSettle();
    expect(find.text('全部二 赞了你的帖子'), findsNothing);
    final Future<void> newPage = state.loadMore();
    repo.requests['interaction:next']!.complete(
      NotificationPage(items: [_notice('互动二')]),
    );
    await newPage;
    await tester.pumpAndSettle();
    expect(find.text('互动二 赞了你的帖子'), findsOneWidget);
  });

  testWidgets('单条已读同步独立分类缓存和未完成请求', (tester) async {
    final repo = _DeferredRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(repository: repo, onOpenPostId: (_) {}),
      ),
    );
    repo.requests['all:first']!.complete(
      NotificationPage(items: [_notice('same')]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NotificationRow));
    await tester.pumpAndSettle();
    await tester.tap(find.text('互动'));
    await tester.pump();
    repo.requests['interaction:first']!.complete(
      NotificationPage(items: [_notice('same')]),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<NotificationRow>(find.byType(NotificationRow)).item.isRead,
      isTrue,
    );
  });

  test('通知目标路由支持帖子评论、用户和社区', () {
    final opened = <String>[];
    final notification = ForumNotification(
      id: 'n1',
      type: 'follow',
      actorId: 'u1',
      actorName: '用户',
      targetType: 'user',
      targetId: 'u2',
      isRead: false,
      createdAt: DateTime.utc(2026, 8, 24),
    );

    NotificationTargetRouter.open(
      notification: notification,
      onOpenPost: (postId, commentId) =>
          opened.add('post:$postId:${commentId ?? ''}'),
      onOpenUser: (userId) => opened.add('user:$userId'),
      onOpenCommunity: (communityId) => opened.add('community:$communityId'),
    );

    expect(opened, ['user:u2']);
  });

  testWidgets('打开通知页不自动全部已读，切换分类改为服务端查询', (tester) async {
    final repository = _RecordingPlatformRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(repository: repository, onOpenPostId: (_) {}),
      ),
    );
    await tester.pump();

    expect(repository.markAllCalls, 0);
    expect(repository.categories, [NotificationCategory.all]);

    await tester.tap(find.text('互动'));
    await tester.pump();

    expect(repository.categories, [
      NotificationCategory.all,
      NotificationCategory.interaction,
    ]);
  });
}

class _DeferredRepository extends _RecordingPlatformRepository {
  final requests = <String, Completer<NotificationPage>>{};
  @override
  Future<NotificationPage> listNotifications({
    String? cursor,
    int limit = 20,
    NotificationCategory category = NotificationCategory.all,
  }) {
    return (requests['${category.value}:${cursor ?? "first"}'] =
            Completer<NotificationPage>())
        .future;
  }

  @override
  Future<void> markNotificationRead(String id) async {}
}

ForumNotification _notice(String id) => ForumNotification(
  id: id,
  type: 'like',
  actorName: id,
  targetType: 'post',
  targetId: 'p1',
  isRead: false,
  createdAt: DateTime.now(),
);
