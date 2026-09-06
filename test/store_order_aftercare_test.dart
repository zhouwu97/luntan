import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/screens/store_order_aftercare_screen.dart';

void main() {
  testWidgets('取消失败后重试保留幂等键，成功后展示实际返还积分', (tester) async {
    var attempts = 0;
    var changed = 0;
    final keys = <String>[];
    var data = <String, dynamic>{'status': 'approved', 'fulfillment_status': 'ready_to_ship'};
    await tester.pumpWidget(MaterialApp(home: StoreOrderAftercareScreen(
      load: () async => data,
      submit: (body, key) async {
        expect(body['action'], 'cancel');
        expect(body['reason'], '不再需要');
        keys.add(key);
        if (++attempts == 1) throw Exception('暂时不可用');
        data = {'status': 'cancelled', 'fulfillment_status': 'cancelled', 'refunded_points': 60};
      },
      onChanged: () => changed++,
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不再需要');
    await tester.tap(find.text('取消订单并返还已扣积分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消订单并返还已扣积分'));
    await tester.pumpAndSettle();
    expect(keys, hasLength(2));
    expect(keys.first, isNotEmpty);
    expect(keys.last, keys.first);
    expect(changed, 1);
    expect(find.text('已返还 60 积分'), findsOneWidget);
    expect(find.text('取消订单并返还已扣积分'), findsNothing);
  });

  testWidgets('管理员退款必须确认收到退货，默认不重新入库', (tester) async {
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(MaterialApp(home: StoreOrderAftercareScreen(
      admin: true,
      load: () async => {'status': 'approved', 'fulfillment_status': 'refund_pending', 'carrier': '顺丰', 'tracking_no': 'RETURN123'},
      submit: (body, key) async { submitted = body; },
      onChanged: () {},
    )));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '确认退货并返还积分');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '已验收');
    await tester.tap(find.text('已实际收到退回商品'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(submitted, containsPair('return_received', true));
    expect(submitted, containsPair('restock', false));
  });
}
