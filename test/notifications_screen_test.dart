import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/notifications_screen.dart';

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
