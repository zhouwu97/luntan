import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/widgets/forum_rules_gate.dart';

Widget _host(ForumRulesGate gate) => MaterialApp(
  home: Scaffold(
    body: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Colors.blue)),
        gate,
      ],
    ),
  ),
);

void main() {
  testWidgets('版规默认折叠：只有超过两行的条文显示展开', (tester) async {
    await tester.pumpWidget(_host(ForumRulesGate(onAgree: () {})));
    await tester.pumpAndSettle();

    // 默认 800x600 测试面下只有超长的第 8 条超过两行，其余完整展示。
    expect(find.text('展开'), findsOneWidget);
    expect(find.text('收起'), findsNothing);

    // 第 8 条在滚动区下方，先滚到可见再点击。
    await tester.ensureVisible(find.text('展开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();

    expect(find.text('收起'), findsOneWidget);
    expect(find.text('展开'), findsNothing);

    await tester.ensureVisible(find.text('收起'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();

    expect(find.text('展开'), findsOneWidget);
  });

  testWidgets('窄屏下被截断的条文显示展开按钮，放得下的不显示', (tester) async {
    // 复现用户反馈的场景：窄屏左右分栏下条文被截断时必须有"展开"。
    // 340 宽时版规区容量为两行 22 字，第 4 条（17 字）放得下，其余 7 条截断。
    tester.view.physicalSize = const Size(340, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(ForumRulesGate(onAgree: () {})));
    await tester.pumpAndSettle();

    expect(find.text('展开'), findsNWidgets(7));

    await tester.tap(find.text('展开').first);
    await tester.pumpAndSettle();

    expect(find.text('收起'), findsOneWidget);
    expect(find.text('展开'), findsNWidgets(6));
  });

  testWidgets('点击同意版规触发 onAgree 回调', (tester) async {
    var agreed = false;
    await tester.pumpWidget(
      _host(ForumRulesGate(onAgree: () => agreed = true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('同意版规，已满18'));
    await tester.pumpAndSettle();

    expect(agreed, isTrue);
  });

  testWidgets('点击不同意展示拒绝页，可返回重新确认版规', (tester) async {
    await tester.pumpWidget(
      _host(ForumRulesGate(onAgree: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('不同意喵，未满18'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未满18不可以进入圣杯酱论坛'), findsOneWidget);
    expect(find.text('返回重新确认'), findsOneWidget);

    await tester.tap(find.text('返回重新确认'));
    await tester.pumpAndSettle();

    expect(find.text('同意版规，已满18'), findsOneWidget);
    expect(find.text('展开'), findsOneWidget);
  });

  test('禁用控制器永不展示弹窗且同意操作无副作用', () async {
    final controller = ForumRulesGateController.disabled();
    await controller.restore();
    expect(controller.shouldShow, isFalse);

    await controller.agree();
    expect(controller.shouldShow, isFalse);
  });

  test('偏好存储不可用时按未同意处理，版规仍会展示', () async {
    // 测试环境没有 mock SharedPreferences 平台通道，restore 内部应吞掉异常。
    final controller = ForumRulesGateController.withPreferences();
    await controller.restore();
    expect(controller.shouldShow, isTrue);

    await controller.agree();
    expect(controller.shouldShow, isFalse);
  });
}
