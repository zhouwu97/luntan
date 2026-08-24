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
  testWidgets('打开消息页不自动全部已读，切换分类改为服务端查询', (tester) async {
    final repository = _RecordingPlatformRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(repository: repository, onOpenPostId: (_) {}),
      ),
    );
    await tester.pump();

    expect(repository.markAllCalls, 0);
    expect(repository.categories, [NotificationCategory.all]);

    await tester.tap(find.text('回复'));
    await tester.pump();

    expect(repository.categories, [
      NotificationCategory.all,
      NotificationCategory.reply,
    ]);
  });
}
