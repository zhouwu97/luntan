import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/widgets/comments/comment_reply_preview.dart';

void main() {
  testWidgets('CommentReplyPreview 渲染 2~3 条二级回复与展开回复按钮', (tester) async {
    bool openedThread = false;
    final replies = [
      Comment(
        id: 'r1',
        postId: 'p1',
        authorId: 'u2',
        author: User(
          id: 'u2',
          username: 'soft',
          nickname: '软萌研究员',
          level: 5,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        content: '新手用普通版就行',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Comment(
        id: 'r2',
        postId: 'p1',
        authorId: 'u3',
        author: User(
          id: 'u3',
          username: 'cat',
          nickname: '夜猫试用员',
          level: 4,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        replyToUserId: 'u2',
        content: '经典版稍微有点紧',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentReplyPreview(
            replies: replies,
            totalReplyCount: 5,
            onOpenThread: () => openedThread = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('软萌研究员', findRichText: true), findsOneWidget);
    expect(find.textContaining('新手用普通版就行', findRichText: true), findsOneWidget);
    expect(find.text('展开 5 条回复 ›'), findsOneWidget);

    await tester.tap(find.text('展开 5 条回复 ›'));
    expect(openedThread, isTrue);
  });
}
