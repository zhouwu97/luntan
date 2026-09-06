import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/widgets/report_reason_sheet.dart';

void main() {
  testWidgets('举报原因返回真实分类，取消不返回 other', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showReportReasonSheet(context);
              },
              child: const Text('举报'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('举报'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('人身攻击、辱骂侵权'));
    await tester.pumpAndSettle();
    expect(result, 'abuse');
    await tester.tap(find.text('举报'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
