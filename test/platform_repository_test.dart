import 'dart:convert';

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
    expect(page.items.single.title, 'User 回复了你的评论');
    expect(page.items.single.category, NotificationCategory.interaction);
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

  test(
    'ForumNotification produces friendly Chinese push notifications and titles',
    () {
      final likeNotif = ForumNotification(
        id: 'n-like',
        type: 'like',
        actorId: 'u-1',
        actorName: '小理酱',
        targetType: 'post',
        targetId: 'p-1',
        isRead: false,
        createdAt: DateTime.now(),
        targetData: const {'post_title': '新人慢玩杯评测'},
      );
      expect(likeNotif.title, '小理酱 赞了你的帖子');
      expect(likeNotif.content, '新人慢玩杯评测');
      expect(likeNotif.category, NotificationCategory.interaction);

      final bookmarkNotif = ForumNotification(
        id: 'n-bm',
        type: 'bookmark',
        actorId: 'u-2',
        actorName: '夜猫试用员',
        targetType: 'post',
        targetId: 'p-1',
        isRead: false,
        createdAt: DateTime.now(),
        targetData: const {},
      );
      expect(bookmarkNotif.title, '夜猫试用员 收藏了你的帖子');

      final replyNotif = ForumNotification(
        id: 'n-reply',
        type: 'comment.created',
        actorId: 'u-3',
        actorName: '软萌研究员',
        targetType: 'post',
        targetId: 'p-1',
        isRead: false,
        createdAt: DateTime.now(),
        targetData: const {'content': '支持楼主，很详细！'},
      );
      expect(replyNotif.title, '软萌研究员 回复了你的评论');
      expect(replyNotif.content, '支持楼主，很详细！');

      final threadReplyNotif = ForumNotification(
        id: 'n-thread-reply',
        type: 'comment.replied',
        actorId: 'u-3',
        actorName: '软萌研究员',
        targetType: 'comment',
        targetId: 'c-1',
        isRead: false,
        createdAt: DateTime.now(),
        targetData: const {'content': '确实好用'},
      );
      expect(threadReplyNotif.title, '软萌研究员 回复了你的评论');
      expect(threadReplyNotif.content, '确实好用');

      final muteNotif = ForumNotification(
        id: 'n-mod',
        type: 'moderation.action',
        actorId: 'u-admin',
        actorName: '管理员',
        targetType: 'moderation_action',
        targetId: 'm-1',
        isRead: false,
        createdAt: DateTime.now(),
        targetData: const {'action': 'mute', 'reason': '含有违规导流信息'},
      );
      expect(muteNotif.title, '账号禁言通知');
      expect(muteNotif.category, NotificationCategory.moderation);

      final appealNotif = ForumNotification(
        id: 'n-appeal',
        type: 'appeal.result',
        actorId: 'u-system',
        actorName: '系统',
        targetType: 'moderation_appeal',
        targetId: 'a-1',
        isRead: false,
        createdAt: DateTime.now(),
        targetData: const {'status': 'approved'},
      );
      expect(appealNotif.title, '申诉已通过');
      expect(appealNotif.category, NotificationCategory.moderation);
    },
  );

  test(
    'PlatformRepository exposes home recommendation management endpoints',
    () async {
      final calls = <String>[];
      final client = ApiClient(
        baseUri: Uri.parse('https://example.com'),
        client: MockClient((request) async {
          calls.add('${request.method} ${request.url.path} ${request.body}');
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/admin/recommendations') {
            return http.Response(
              '{"items":[{"post_id":"p1","position":1,"recommended_by":"admin-1","recommended_at":"2026-08-26T01:00:00Z","expires_at":null,"post":{"id":"p1","title":"开箱记录","content":"正文","author":{"nickname":"管理员"},"community":{"name":"大型拆箱"}}}]}',
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response('{"success":true}', 200);
        }),
      );
      final repository = ApiPlatformRepository(client);

      final recommendations = await repository.listHomeRecommendations();
      await repository.setHomeRecommendation(
        postId: 'p1',
        position: 2,
        expiresAt: DateTime.utc(2026, 9, 1),
      );
      await repository.removeHomeRecommendation('p1');
      await repository.reorderHomeRecommendations(['p2', 'p1']);

      expect(recommendations.single.postId, 'p1');
      expect(recommendations.single.title, '开箱记录');
      expect(recommendations.single.communityName, '大型拆箱');
      expect(calls.first, 'GET /api/v1/admin/recommendations ');
      expect(
        calls[1].startsWith('PUT /api/v1/admin/recommendations/p1 '),
        isTrue,
      );
      expect(jsonDecode(calls[1].substring(calls[1].indexOf('{'))) as Map, {
        'position': 2,
        'expires_at': '2026-09-01T00:00:00.000Z',
      });
      expect(calls[2], 'DELETE /api/v1/admin/recommendations/p1 ');
      expect(
        calls[3].startsWith('PUT /api/v1/admin/recommendations/reorder '),
        isTrue,
      );
      expect(jsonDecode(calls[3].substring(calls[3].indexOf('{'))) as Map, {
        'items': [
          {'post_id': 'p2', 'position': 0},
          {'post_id': 'p1', 'position': 1},
        ],
      });
      client.close();
    },
  );
}
