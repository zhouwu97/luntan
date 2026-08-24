import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/publish_repository.dart';
import 'package:luntan/widgets/composer_sheet.dart';

void main() {
  testWidgets('发布失败时保留编辑器内容并允许原地重试', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => PostEditorDialog(
                isGameShare: false,
                onPublish: (_) async {
                  attempts += 1;
                  if (attempts == 1) {
                    throw const PublishException('网络断开，请重试');
                  }
                },
              ),
            ),
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '保留下来的标题');
    await tester.enterText(find.byType(TextField).at(1), '保留下来的正文');
    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pumpAndSettle();

    expect(find.byType(PostEditorDialog), findsOneWidget);
    expect(find.text('网络断开，请重试'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '保留下来的标题',
    );

    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(PostEditorDialog), findsNothing);
  });
}
