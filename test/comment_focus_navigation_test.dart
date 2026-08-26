import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/controllers/comments_controller.dart';
import 'package:luntan/controllers/interaction_controller.dart';
import 'package:luntan/controllers/post_detail_controller.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/screens/post_detail_screen.dart';
import 'package:luntan/widgets/comments/comment_item.dart';
import 'package:luntan/widgets/comments/comment_thread_sheet.dart';

void main() {
  testWidgets('指定 focusCommentId 为一级评论时正确定位并高亮', (tester) async {
    final postRepo = MockPostRepository();
    final commentRepo = MockCommentRepository();
    final interactionRepo = MockInteractionRepository();

    final postDetailController = PostDetailController(
      repository: postRepo,
      postId: 'u4',
    );
    final commentsController = CommentsController(
      repository: commentRepo,
      postId: 'u4',
    );
    final interactionController = InteractionController(
      repository: interactionRepo,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailScreen(
          controller: postDetailController,
          commentsController: commentsController,
          interactionController: interactionController,
          currentUserId: 'u1',
          focusCommentId: 'comment-u4-1',
          onToggleLike: (_) async {},
          onToggleBookmark: (_) async {},
          onFeedback: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(CommentItem), findsWidgets);
    expect(find.textContaining('包装比我想象中扎实'), findsOneWidget);
  });

  testWidgets('指定 focusCommentId 为二级回复时自动展开楼中楼并定位高亮', (tester) async {
    final postRepo = MockPostRepository();
    final commentRepo = MockCommentRepository();
    final interactionRepo = MockInteractionRepository();

    final postDetailController = PostDetailController(
      repository: postRepo,
      postId: 'u4',
    );
    final commentsController = CommentsController(
      repository: commentRepo,
      postId: 'u4',
    );
    final interactionController = InteractionController(
      repository: interactionRepo,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailScreen(
          controller: postDetailController,
          commentsController: commentsController,
          interactionController: interactionController,
          currentUserId: 'u1',
          focusCommentId: 'comment-u4-1-1',
          onToggleLike: (_) async {},
          onToggleBookmark: (_) async {},
          onFeedback: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 楼中楼 Sheet 应该已自动弹出
    expect(find.byType(CommentThreadSheet), findsOneWidget);

    // 消耗高亮计时器
    await tester.pump(const Duration(seconds: 2));
  });
}
