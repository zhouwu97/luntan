import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/controllers/comments_controller.dart';
import 'package:luntan/controllers/interaction_controller.dart';
import 'package:luntan/controllers/post_detail_controller.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/screens/post_detail_screen.dart';

void main() {
  testWidgets('PostDetailScreen 正确渲染一级评论列表与发布新评论', (tester) async {
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
          isAuthenticated: true,
          onToggleLike: (_) async {},
          onToggleBookmark: (_) async {},
          onFeedback: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 检查帖子标题与一级评论
    expect(find.text('开箱记录：第一次买大尺寸倒模'), findsOneWidget);
    expect(find.textContaining('包装比我想象中扎实'), findsOneWidget);

    // 在底部输入栏输入新评论并发送
    await tester.enterText(find.byType(TextField).first, '我也觉得收纳很重要！');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(find.text('我也觉得收纳很重要！'), findsOneWidget);
  });
}
