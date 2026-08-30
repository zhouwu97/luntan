import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/screens/exchange_store_screen.dart';

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
    expect(find.text('600 积分'), findsOneWidget);
    expect(find.text('发帖 +5 · 点赞 +1 · 评论 +1 · 每天最多获得 20 积分'), findsOneWidget);
    expect(find.text('主题贴纸包'), findsNothing);
    expect(find.text('校园钥匙扣'), findsNothing);
    expect(find.text('校园帆布袋'), findsNothing);
    await tester.ensureVisible(find.text('兑换').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('兑换').first);
    await tester.pumpAndSettle();

    expect(store.points, 3920);
    await tester.scrollUntilVisible(
      find.text('我的兑换'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('我的兑换'), findsOneWidget);
    expect(find.text('待领取'), findsOneWidget);
    expect(find.text('还没有兑换记录'), findsNothing);
  });
}
