import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/screens/app_update_sheet.dart';

void main() {
  // 测试环境没有注入 API_BASE_URL，弹层检查会停在 error 分支，
  // 但关闭入口与关闭路径的行为正是需要验证的部分。
  Future<void> openSheet(WidgetTester tester, {required bool force}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showAppUpdateSheet(context, force: force);
                },
                child: const Text('打开更新弹层'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开更新弹层'));
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);
  }

  testWidgets('普通检查更新弹层保留关闭按钮，点遮罩可关闭', (tester) async {
    await openSheet(tester, force: false);

    expect(find.byTooltip('关闭'), findsOneWidget);
    await tester.tapAt(const Offset(20, 30));
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsNothing);
  });

  testWidgets('强制更新弹层没有关闭入口，点遮罩与返回键都无法关闭', (tester) async {
    await openSheet(tester, force: true);

    expect(find.byTooltip('关闭'), findsNothing);

    await tester.tapAt(const Offset(20, 30));
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);

    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);
  });
}
