import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/widgets/comments/comment_thread_sheet.dart';

void main() {
  testWidgets('CommentThreadSheet 展示根评论摘要并支持二级回复', (tester) async {
    final commentRepo = MockCommentRepository();
    final rootComment = Comment(
      id: 'comment-u4-1',
      postId: 'u4',
      authorId: 'user-2',
      author: User(
        id: 'user-2',
        username: 'soft_lab',
        nickname: '软萌研究员',
        level: 6,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      content: '包装比我想象中扎实，重量也确实有点分量。',
      replyCount: 2,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentThreadSheet(
            rootComment: rootComment,
            repository: commentRepo,
            blockedMessage: '禁言中',
            onReply: (target, content) async {
              return commentRepo.createReply(
                commentId: rootComment.id,
                content: content,
                replyToUserId: target.authorId,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 检查根评论摘要与二级回复列表
    expect(find.text('2 条回复'), findsOneWidget);
    expect(find.text('包装比我想象中扎实，重量也确实有点分量。'), findsOneWidget);

    // 回复二级评论
    expect(find.text('回复'), findsWidgets);
    await tester.tap(find.text('回复').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('回复 @'), findsWidgets);
  });
}
