import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';

void main() {
  test('PlatformRepository maps notification and moderation endpoints', () async {
    final calls = <String>[];
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        calls.add(
          '${request.method} ${request.url.path}'
          '${request.url.hasQuery ? '?${request.url.query}' : ''}',
        );
        if (request.url.path == '/api/v1/notifications') {
          return http.Response(
            '{"items":[{"id":"n1","type":"reply","actor":{"id":"u1","nickname":"User"},"target_type":"post","target_id":"p1","is_read":false,"created_at":"2026-08-22T00:00:00Z"}],"has_more":false}',
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    final repository = ApiPlatformRepository(client);

    final page = await repository.listNotifications(
      category: NotificationCategory.reply,
    );
    await repository.markNotificationRead('n1');
    await repository.markAllNotificationsRead();
    await repository.report(
      targetType: 'post',
      targetId: 'p1',
      reasonCode: 'spam',
    );
    await repository.setBlock(userId: 'u2', active: true);
    await repository.setBlock(userId: 'u2', active: false);

    expect(page.items.single.actorName, 'User');
    expect(calls, [
      'GET /api/v1/notifications?limit=20&category=reply',
      'PATCH /api/v1/notifications/n1/read',
      'POST /api/v1/notifications/read-all',
      'POST /api/v1/reports',
      'PUT /api/v1/users/u2/block',
      'DELETE /api/v1/users/u2/block',
    ]);
    client.close();
  });
}
