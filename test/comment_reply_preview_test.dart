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

  testWidgets('CommentReplyPreview 按点赞数展示前4条二级回复，多余折叠，点击回复项触发 onReplyTap', (
    tester,
  ) async {
    Comment? tappedReply;
    final replies = List.generate(
      6,
      (i) => Comment(
        id: 'reply-$i',
        postId: 'p1',
        authorId: 'u$i',
        author: User(
          id: 'u$i',
          username: 'user_$i',
          nickname: '用户$i',
          level: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        likeCount: i * 10,
        content: '回复内容_$i',
        createdAt: DateTime.now().add(Duration(minutes: i)),
        updatedAt: DateTime.now(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentReplyPreview(
            replies: replies,
            totalReplyCount: 11,
            onOpenThread: () {},
            onReplyTap: (r) => tappedReply = r,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 应该只展示点赞数最高的 4 条（reply-5, reply-4, reply-3, reply-2）
    expect(find.textContaining('用户5', findRichText: true), findsOneWidget);
    expect(find.textContaining('用户4', findRichText: true), findsOneWidget);
    expect(find.textContaining('用户3', findRichText: true), findsOneWidget);
    expect(find.textContaining('用户2', findRichText: true), findsOneWidget);
    expect(find.textContaining('用户1', findRichText: true), findsNothing);
    expect(find.textContaining('用户0', findRichText: true), findsNothing);

    // 折叠按钮展示全部总数
    expect(find.text('查看全部 11 条回复 ›'), findsOneWidget);

    // 点击某一条回复预览，触发 onReplyTap
    final inkWellRect = tester.getRect(find.byType(InkWell).first);
    await tester.tapAt(inkWellRect.centerRight - const Offset(10, 0));
    await tester.pumpAndSettle();
    expect(tappedReply?.id, 'reply-5');
  });
}



