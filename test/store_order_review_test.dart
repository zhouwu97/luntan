import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/store_order_review_screen.dart';

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets('兑换审核工作台展示申请详情并提交审核决定', (tester) async {
    String? reviewedDecision;
    String? openedUserId;
    int? openedTab;
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/admin/store/orders') {
        return _json({
          'items': [
            {
              'id': 'order-1',
              'user_id': 'user-1',
              'username': 'user_one',
              'nickname': '测试用户',
              'product_id': 'badge',
              'product_name': '论坛纪念徽章',
              'points': 600,
              'status': 'pending_review',
              'user_points': 638,
              'created_at': '2026-08-31T12:00:00Z',
            },
          ],
        });
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/admin/store/orders/order-1') {
        return _json({
          'id': 'order-1',
          'user_id': 'user-1',
          'username': 'user_one',
          'nickname': '测试用户',
          'product_id': 'badge',
          'product_name': '论坛纪念徽章',
          'points': 600,
          'status': 'pending_review',
          'user_points': 638,
          'reserved_points': 600,
          'available_points': 38,
          'created_at': '2026-08-31T12:00:00Z',
          'point_sources': [
            {'source': 'post', 'points': 300, 'count': 60},
            {'source': 'comment', 'points': 338, 'count': 338},
          ],
        });
      }
      if (request.method == 'GET' &&
          request.url.path ==
              '/api/v1/admin/store/orders/order-1/reward-content') {
        return _json({
          'items': [
            {
              'id': 'tx-post-1',
              'source': 'post',
              'target_type': 'post',
              'target_id': 'post-1',
              'points': 5,
              'reason': '发帖奖励',
              'earned_at': '2026-08-30T12:00:00Z',
              'title_at_reward': '一篇有帮助的分享',
              'content_at_reward': '这是获得积分时的原始内容。',
              'current_title': '一篇有帮助的分享',
              'current_content': '这是获得积分时的原始内容。',
              'current_status': 'normal',
              'edited_since_reward': false,
              'snapshot_available': true,
            },
          ],
        });
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/admin/store/orders/order-1/review') {
        reviewedDecision = jsonDecode(request.body)['decision'] as String;
        return _json({'id': 'order-1', 'status': 'approved'});
      }
      return _json({'message': 'not found'}, 404);
    });
    final repository = PlatformRepository(
      ApiClient(baseUri: Uri.parse('https://example.com'), client: client),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StoreOrderReviewScreen(
          repository: repository,
          onOpenUserActivity: (userId, tab) {
            openedUserId = userId;
            openedTab = tab;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('兑换审核'), findsOneWidget);
    expect(find.text('测试用户'), findsOneWidget);
    await tester.tap(find.text('测试用户'));
    await tester.pumpAndSettle();

    expect(find.text('论坛纪念徽章'), findsOneWidget);
    expect(find.text('查看他的发帖'), findsOneWidget);
    expect(find.text('发帖奖励'), findsOneWidget);
    await tester.tap(find.text('查看他的评论'));
    expect(openedUserId, 'user-1');
    expect(openedTab, 1);
    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('获得积分的内容记录'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    await tester.tap(find.text('审核通过'));
    await tester.pumpAndSettle();
    expect(find.text('确认通过兑换申请？'), findsOneWidget);
    await tester.tap(find.text('确认通过'));
    await tester.pumpAndSettle();
    expect(reviewedDecision, 'approve');
  });
}
