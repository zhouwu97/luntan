import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/comment_repository.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/screens/comment_thread_screen.dart';

void main() {
  testWidgets('CommentThreadScreen 展示根评论摘要并支持二级回复', (tester) async {
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
        home: CommentThreadScreen(
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
    );
    await tester.pumpAndSettle();

    expect(find.text('2 条回复'), findsOneWidget);
    expect(find.text('包装比我想象中扎实，重量也确实有点分量。'), findsOneWidget);
    expect(find.text('回复'), findsWidgets);
    await tester.tap(find.text('回复').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('回复 @'), findsWidgets);
  });

  testWidgets('楼中楼加载失败时不显示确定性的 0 条回复', (tester) async {
    final root = Comment(
      id: 'root-1',
      postId: 'post-1',
      authorId: 'user-1',
      content: '根评论',
      createdAt: DateTime(2026, 8, 27),
      updatedAt: DateTime(2026, 8, 27),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CommentThreadScreen(
          rootComment: root,
          repository: _FailingCommentRepository(),
          blockedMessage: '暂不能回复',
          onReply: (_, _) async => throw StateError('not used'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('回复加载失败，请重试'), findsOneWidget);
    expect(find.text('0 条回复'), findsNothing);
    expect(find.text('点击重试'), findsOneWidget);
  });
}

class _FailingCommentRepository implements CommentRepository {
  @override
  Future<CommentPage> listComments({
    required String postId,
    int limit = 20,
    int offset = 0,
    CommentSort? sort,
    String? authorId,
  }) => throw StateError('not used');

  @override
  Future<CommentPage> listReplies({
    required String commentId,
    String? cursor,
    int limit = 20,
  }) async => throw StateError('replies unavailable');

  @override
  Future<Comment> createComment({
    required String postId,
    required String content,
    String? parentId,
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
  }) => throw StateError('not used');

  @override
  Future<Comment> createReply({
    required String commentId,
    required String content,
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
  }) => throw StateError('not used');

  @override
  Future<void> deleteComment(String commentId) => throw StateError('not used');
}
