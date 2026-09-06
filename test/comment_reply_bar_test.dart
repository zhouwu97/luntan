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

  testWidgets('游客点击评论图片时先引导注册，不打开系统图片选择器', (tester) async {
    var requireAuthCalls = 0;
    String? feedback;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CommentReplyBar(
            isSheetMode: true,
            isAuthenticated: true,
            canComment: true,
            canUploadMedia: false,
            onRequireAuth: () => requireAuthCalls++,
            blockedMessage: '当前身份暂不能评论',
            onFeedback: (message) => feedback = message,
            onCancelTarget: () {},
            onSubmit: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加图片'));
    await tester.pump();

    expect(requireAuthCalls, 1);
    expect(feedback, '注册正式账号后即可添加评论图片');
  });
}
