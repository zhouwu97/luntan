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
    String? requestedStatus;
    String? openedUserId;
    int? openedTab;
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/admin/store/orders') {
        requestedStatus = request.url.queryParameters['status'];
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

    expect(find.text('兑换订单'), findsOneWidget);
    expect(find.text('测试用户'), findsOneWidget);
    expect(requestedStatus, 'pending_review');
    await tester.tap(find.text('已拒绝'));
    await tester.pumpAndSettle();
    expect(requestedStatus, 'rejected');
    await tester.tap(find.text('测试用户'));
    await tester.pumpAndSettle();

    expect(find.text('论坛纪念徽章'), findsOneWidget);
    expect(find.text('申请时间'), findsOneWidget);
    expect(find.text('申请 / 截止'), findsNothing);
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

  test('兑换审核仓库解析奖励分页并提交人工排除流水', () async {
    Map<String, dynamic>? reviewBody;
    Map<String, dynamic>? shipBody;
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path ==
              '/api/v1/admin/store/orders/order-1/reward-content') {
        expect(request.url.queryParameters['limit'], '1');
        expect(request.url.queryParameters['source'], 'comment');
        return _json({
          'items': [
            {
              'id': 'tx-comment-1',
              'source': 'comment',
              'target_type': 'comment',
              'target_id': 'comment-1',
              'points': 1,
              'reason': '评论奖励',
              'earned_at': '2026-08-31T12:00:00Z',
              'title_at_reward': '帖子标题',
              'content_at_reward': '666',
              'current_title': '帖子标题',
              'current_content': '666',
              'current_status': 'normal',
              'edited_since_reward': false,
              'snapshot_available': true,
              'invalidated': false,
            },
          ],
          'next_cursor': 'next-1',
          'has_more': true,
        });
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/admin/store/orders/order-1/review') {
        reviewBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'id': 'order-1', 'status': 'approved'});
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/admin/store/orders/order-1/ship') {
        shipBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'id': 'order-1',
          'status': 'approved',
          'fulfillment_status': 'shipped',
        });
      }
      return _json({'message': 'not found'}, 404);
    });
    final repository = PlatformRepository(
      ApiClient(baseUri: Uri.parse('https://example.com'), client: client),
    );

    final page = await repository.getStoreOrderRewardContentPage(
      'order-1',
      limit: 1,
      source: 'comment',
    );
    expect(page.items.single.invalidated, false);
    expect(page.items.single.contentAtReward, '666');
    expect(page.nextCursor, 'next-1');
    expect(page.hasMore, true);

    await repository.reviewStoreOrder(
      id: 'order-1',
      decision: 'approve',
      invalidTransactionIds: const ['tx-comment-1'],
    );
    expect(reviewBody?['invalid_transaction_ids'], ['tx-comment-1']);

    await repository.shipStoreOrder(
      id: 'order-1',
      carrier: '顺丰速运',
      trackingNo: 'SF1234567890',
    );
    expect(shipBody?['carrier'], '顺丰速运');
    expect(shipBody?['tracking_no'], 'SF1234567890');
  });

  testWidgets('兑换订单待发货详情提交物流信息', (tester) async {
    String? requestedStatus;
    Map<String, dynamic>? shipBody;
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/admin/store/orders') {
        requestedStatus = request.url.queryParameters['status'];
        if (requestedStatus != 'ready_to_ship') {
          return _json({'items': []});
        }
        return _json({
          'items': [
            {
              'id': 'order-ship',
              'user_id': 'user-1',
              'username': 'user_one',
              'nickname': '测试用户',
              'product_id': 'badge',
              'product_name': '论坛纪念徽章',
              'points': 600,
              'status': 'approved',
              'fulfillment_status': 'ready_to_ship',
              'user_points': 38,
              'created_at': '2026-08-31T12:00:00Z',
              'shipping': {
                'recipient_name': '张三',
                'phone': '13800000000',
                'province': '辽宁省',
                'city': '沈阳市',
                'district': '浑南区',
                'address_detail': '宿舍楼 101',
                'masked_name': '张*',
                'masked_phone': '138****0000',
                'masked_address': '辽宁省沈阳市浑南区 ********',
              },
            },
          ],
        });
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/admin/store/orders/order-ship') {
        return _json({
          'id': 'order-ship',
          'user_id': 'user-1',
          'username': 'user_one',
          'nickname': '测试用户',
          'product_id': 'badge',
          'product_name': '论坛纪念徽章',
          'points': 600,
          'status': 'approved',
          'fulfillment_status': 'ready_to_ship',
          'user_points': 38,
          'reserved_points': 0,
          'available_points': 38,
          'created_at': '2026-08-31T12:00:00Z',
          'point_sources': [],
          'shipping': {
            'recipient_name': '张三',
            'phone': '13800000000',
            'province': '辽宁省',
            'city': '沈阳市',
            'district': '浑南区',
            'address_detail': '宿舍楼 101',
            'submitted_at': '2026-08-31T13:00:00Z',
          },
        });
      }
      if (request.method == 'GET' &&
          request.url.path ==
              '/api/v1/admin/store/orders/order-ship/reward-content') {
        return _json({'items': []});
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/admin/store/orders/order-ship/ship') {
        shipBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'id': 'order-ship',
          'status': 'approved',
          'fulfillment_status': 'shipped',
        });
      }
      return _json({'message': 'not found'}, 404);
    });
    final repository = PlatformRepository(
      ApiClient(baseUri: Uri.parse('https://example.com'), client: client),
    );

    await tester.pumpWidget(
      MaterialApp(home: StoreOrderReviewScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('待发货'));
    await tester.pumpAndSettle();
    expect(requestedStatus, 'ready_to_ship');
    await tester.tap(find.text('测试用户'));
    await tester.pumpAndSettle();

    expect(find.text('收货与物流'), findsOneWidget);
    expect(find.text('张三'), findsOneWidget);
    await tester.tap(find.text('确认发货'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '顺丰速运');
    await tester.enterText(find.byType(TextFormField).at(1), 'SF1234567890');
    await tester.tap(find.widgetWithText(FilledButton, '确认发货').last);
    await tester.pumpAndSettle();

    expect(shipBody?['carrier'], '顺丰速运');
    expect(shipBody?['tracking_no'], 'SF1234567890');
  });
}
