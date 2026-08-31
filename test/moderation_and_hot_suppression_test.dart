import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/screens/image_moderation_screen.dart';
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

    expect(find.text('图片处理 (1/1)'), findsOneWidget);
    expect(find.text('马赛克'), findsOneWidget);
    expect(find.text('毛玻璃模糊'), findsOneWidget);
    expect(find.text('保存打码'), findsOneWidget);

    // Switch to blur
    await tester.tap(find.text('毛玻璃模糊'));
    await tester.pump();
  });
}
