import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/widgets/comments/comment_reply_bar.dart';
import 'package:luntan/widgets/comments/comment_composer_controller.dart';

void main() {
  testWidgets('输入评论文本后发送按钮立即可用', (tester) async {
    final composer = CommentComposerController();
    addTearDown(composer.dispose);
    var submitted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CommentReplyBar(
            composerController: composer,
            isSheetMode: true,
            blockedMessage: '当前身份暂不能评论',
            onFeedback: (_) {},
            onCancelTarget: () {},
            onSubmit: () => submitted = true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '回归评论');
    await tester.pump();

    final sendButton = find.widgetWithText(FilledButton, '发送');
    expect(tester.widget<FilledButton>(sendButton).onPressed, isNotNull);
    await tester.tap(sendButton);
    expect(submitted, isTrue);
  });
}
