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
    expect(find.text('查看全部 5 条回复 ›'), findsOneWidget);

    await tester.tap(find.text('查看全部 5 条回复 ›'));
    expect(openedThread, isTrue);
  });

  testWidgets('CommentReplyPreview 作者与被回复人真实点击触发 onAuthorTap', (tester) async {
    final tappedIds = <String>[];
    Comment? tappedReply;
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
        replyToUserId: 'u3',
        replyToUser: User(
          id: 'u3',
          username: 'cat',
          nickname: '夜猫试用员',
          level: 4,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        content: '新手用普通版就行',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentReplyPreview(
            replies: replies,
            totalReplyCount: 1,
            onOpenThread: () {},
            onReplyTo: (reply) => tappedReply = reply,
            onAuthorTap: (id) => tappedIds.add(id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 点击作者
    await tester.tap(find.text('软萌研究员'));
    await tester.pumpAndSettle();
    expect(tappedIds, contains('u2'));

    // 点击被回复人
    await tester.tap(find.text('@夜猫试用员'));
    await tester.pumpAndSettle();
    expect(tappedIds, contains('u3'));

    // 点击回复整条内容区域触发 onReplyTo (点击右侧空白避免命中子 span 的 GestureDetector)
    final inkWellRect = tester.getRect(find.byType(InkWell).first);
    await tester.tapAt(inkWellRect.centerRight - const Offset(10, 0));
    await tester.pumpAndSettle();
    expect(tappedReply?.id, 'r1');
  });
}



