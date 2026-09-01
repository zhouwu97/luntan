import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/controllers/comments_controller.dart';
import 'package:luntan/controllers/interaction_controller.dart';
import 'package:luntan/controllers/post_detail_controller.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/domain/repositories.dart';
import 'package:luntan/screens/image_moderation_screen.dart';
import 'package:luntan/screens/post_detail_screen.dart';
import 'package:luntan/widgets/forum_post_card.dart';

void main() {
  testWidgets('ForumPostCard renders [已人工移出热门] badge when hotSuppressed is true', (tester) async {
    final post = Post(
      id: 'p101',
      authorId: 'u1',
      communityId: 'c1',
      title: '热门测试帖子',
      content: '测试内容',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      hotSuppressed: true,
      hotSuppressedReason: '人工移出热门',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumPostCard(
            post: post,
            onOpen: () {},
            onLike: () {},
            onBookmark: () {},
          ),
        ),
      ),
    );

    expect(find.text('已人工移出热门'), findsOneWidget);
  });

  testWidgets('ImageModerationScreen displays image and allows switching masking mode', (tester) async {
    final media = MediaAsset(
      id: 'm101',
      type: MediaType.image,
      url: 'https://example.com/photo.jpg',
      width: 800,
      height: 600,
      moderationStatus: 'normal',
      maskRegions: const [
        MaskRegion(x: 0.1, y: 0.1, width: 0.3, height: 0.3, type: 'mosaic'),
      ],
    );

    final post = Post(
      id: 'p101',
      authorId: 'u1',
      communityId: 'c1',
      title: '打码测试帖子',
      content: '测试内容',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      media: [media],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ImageModerationScreen(post: post),
      ),
    );

    expect(find.text('图片打码 1/1'), findsOneWidget);
    expect(find.text('马赛克'), findsOneWidget);
    expect(find.text('模糊'), findsOneWidget);
    expect(find.text('保存并应用'), findsOneWidget);

    // Switch to blur
    await tester.tap(find.text('模糊'));
    await tester.pump();
  });

  testWidgets('PostDetailScreen 显示图片打码入口并支持跳转（管理员且有图）', (tester) async {
    final postRepo = _FakePostWithImageRepository();
    final commentRepo = MockCommentRepository();
    final interactionRepo = MockInteractionRepository();
    final platformRepo = MockPlatformRepository();

    final postDetailController = PostDetailController(
      repository: postRepo,
      postId: 'p-with-img',
    );
    final commentsController = CommentsController(
      repository: commentRepo,
      postId: 'p-with-img',
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
          platformRepository: platformRepo,
          canModerate: true,
          onToggleLike: (_) async {},
          onToggleBookmark: (_) async {},
          onFeedback: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 打开右上角更多菜单
    final appBarMoreButton = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.more_horiz_rounded),
    );
    await tester.tap(appBarMoreButton);
    await tester.pumpAndSettle();

    expect(find.text('图片打码'), findsOneWidget);
    expect(find.text('对帖子图片进行马赛克或模糊处理'), findsOneWidget);

    // 点击图片打码进入 ImageModerationScreen
    await tester.tap(find.text('图片打码'));
    await tester.pumpAndSettle();

    expect(find.byType(ImageModerationScreen), findsOneWidget);
  });

  testWidgets('PostDetailScreen 无管理员权限时不展示图片打码入口', (tester) async {
    final postRepo = _FakePostWithImageRepository();
    final commentRepo = MockCommentRepository();
    final interactionRepo = MockInteractionRepository();
    final platformRepo = MockPlatformRepository();

    final postDetailController = PostDetailController(
      repository: postRepo,
      postId: 'p-with-img',
    );
    final commentsController = CommentsController(
      repository: commentRepo,
      postId: 'p-with-img',
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
          platformRepository: platformRepo,
          canModerate: false, // 普通用户
          onToggleLike: (_) async {},
          onToggleBookmark: (_) async {},
          onFeedback: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 打开右上角更多菜单
    final appBarMoreButton = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.more_horiz_rounded),
    );
    await tester.tap(appBarMoreButton);
    await tester.pumpAndSettle();

    expect(find.text('图片打码'), findsNothing);
  });
}

class _FakePostWithImageRepository implements PostRepository {
  @override
  Future<PostDetail?> getPost(String id) async {
    final media = MediaAsset(
      id: 'm101',
      type: MediaType.image,
      url: 'https://example.com/photo.jpg',
      width: 800,
      height: 600,
      moderationStatus: 'normal',
    );
    final post = Post(
      id: id,
      authorId: 'u1',
      communityId: 'c1',
      title: '打码测试帖子',
      content: '测试内容',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      media: [media],
    );
    return PostDetail(post: post);
  }
}
