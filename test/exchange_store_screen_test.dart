import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/store_repository.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/screens/exchange_store_screen.dart';

http.Response _json(Object payload, [int status = 200]) => http.Response(
  jsonEncode(payload),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets('兑换商店只展示确认的三项周边与固定积分规则', (tester) async {
    final store = ForumStore.uiOnly();
    await tester.pumpWidget(
      MaterialApp(home: ExchangeStoreScreen(store: store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('论坛纪念徽章'), findsOneWidget);
    expect(find.text('论坛纪念立牌'), findsOneWidget);
    expect(find.text('200元杯子盲盒（可许愿）'), findsOneWidget);
    expect(find.text('60 积分'), findsOneWidget);
    expect(find.text('300 积分'), findsOneWidget);
    expect(find.text('1000 积分'), findsOneWidget);
    // 规则行是 Text.rich（金色加成数字），按纯文本整体匹配。
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data ?? widget.textSpan?.toPlainText()) ==
                '发帖 +5 · 点赞 +1 · 评论 +1 · 每天最多获得 20 积分',
      ),
      findsOneWidget,
    );
    expect(find.text('主题贴纸包'), findsNothing);
    expect(find.text('校园钥匙扣'), findsNothing);
    expect(find.text('校园帆布袋'), findsNothing);
    await tester.ensureVisible(find.text('兑换').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('兑换').first);
    await tester.pumpAndSettle();

    expect(store.points, 3980);
    await tester.scrollUntilVisible(
      find.text('我的兑换'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('我的兑换'), findsOneWidget);
    expect(find.text('待审核'), findsOneWidget);
    expect(find.text('还没有兑换记录'), findsNothing);
  });

  testWidgets('兑换失败后重试复用同一个幂等键，成功后换新键', (tester) async {
    var redeemAttempts = 0;
    final redeemKeys = <String>[];
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/api/v1/store/products':
          return _json({
            'items': [
              {
                'id': 'p1',
                'name': '论坛纪念徽章',
                'description': '纪念徽章',
                'emoji': '🏅',
                'points': 60,
                'color': 4284760319,
                'redeemed_count': 3,
              },
            ],
          });
        case '/api/v1/me/points':
          return _json({'balance': 100, 'transactions': []});
        case '/api/v1/me/store-orders':
          return _json({'items': []});
        case '/api/v1/store/orders':
          redeemAttempts++;
          redeemKeys.add(request.headers['Idempotency-Key'] ?? '');
          if (redeemAttempts == 1) {
            return _json({'code': 'INTERNAL', 'message': 'boom'}, 500);
          }
          return _json({
            'id': 'o1',
            'product_id': 'p1',
            'product_name': '论坛纪念徽章',
            'points': 60,
            'status': 'pending',
            'created_at': '2026-08-30T10:00:00Z',
          });
      }
      return _json({'message': 'not found'}, 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ExchangeStoreScreen(
          apiRepository: StoreRepository(
            ApiClient(
              baseUri: Uri.parse('https://example.com'),
              client: client,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tapRedeem() async {
      await tester.ensureVisible(find.text('兑换').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('兑换').first);
      await tester.pumpAndSettle();
    }

    await tapRedeem();
    expect(redeemAttempts, 1);
    expect(find.byType(SnackBar), findsOneWidget);

    await tapRedeem();
    expect(redeemAttempts, 2);
    expect(redeemKeys, hasLength(2));
    expect(redeemKeys.first, isNotEmpty);
    expect(redeemKeys[1], redeemKeys.first);

    // 成功之后再次兑换同一商品应生成新的幂等键。
    await tapRedeem();
    expect(redeemAttempts, 3);
    expect(redeemKeys[2], isNot(redeemKeys.first));
  });
}
