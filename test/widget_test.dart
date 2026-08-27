import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/app.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/screens/post_detail_screen.dart';
import 'package:luntan/widgets/comments/comment_item.dart';
import 'package:luntan/widgets/forum_post_card.dart';
import 'package:luntan/widgets/post_media_preview.dart';
import 'package:luntan/widgets/search/search_post_row.dart';

void main() {
  testWidgets('首页展示论坛骨架并可以切换我的页面', (tester) async {
    await tester.pumpWidget(const LuntanApp());
    expect(find.text('大型拆箱'), findsWidgets);
    expect(find.text('推荐'), findsWidgets);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('常用功能'), findsOneWidget);
    expect(find.text('兑换商店'), findsOneWidget);
  });

  testWidgets('首页帖子标题点击通过 ID 路由打开详情', (tester) async {
    await tester.pumpWidget(const LuntanApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('大型拆箱').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('为啥很少朋友推荐星野爱丽丝2代？'));
    await tester.pumpAndSettle();

    expect(find.byType(PostDetailScreen), findsOneWidget);
  });

  testWidgets('开箱帖子详情显示评论并保留楼中楼入口', (tester) async {
    await tester.pumpWidget(const LuntanApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('大型拆箱').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('为啥很少朋友推荐星野爱丽丝2代？'));
    await tester.pumpAndSettle();

    expect(find.text('评论 24'), findsOneWidget);
    expect(find.byType(CommentItem), findsWidgets);
  });

  testWidgets('首页最新排序下显示按回复与按发帖胶囊并支持切换', (tester) async {
    await tester.pumpWidget(const LuntanApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('最新'));
    await tester.pumpAndSettle();

    expect(find.text('按回复'), findsOneWidget);
    expect(find.text('按发帖'), findsOneWidget);

    await tester.tap(find.text('按发帖'));
    await tester.pumpAndSettle();
  });

  testWidgets('帖子图片点击转发到卡片的详情回调', (tester) async {
    var opened = false;
    final samplePost = ForumStore.seeded().posts.first;
    final postWithImage = Post(
      id: 'test-p-img',
      authorId: samplePost.authorId,
      author: samplePost.author,
      communityId: samplePost.communityId,
      community: samplePost.community,
      title: '带图帖子测试',
      content: '带图帖子内容',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      media: const [
        MediaAsset(
          id: 'img1',
          type: MediaType.image,
          url: 'https://example.com/1.png',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumPostCard(
            post: postWithImage,
            onOpen: () => opened = true,
            onOpenComments: () {},
            onLike: () {},
            onBookmark: () {},
            onMenu: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PostMediaPreview).first);

    expect(opened, isTrue);
  });

  testWidgets('帖子媒体预览保持源比例且不裁切', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: PostMediaPreview(
              images: [
                MediaAsset(
                  id: 'tall-image',
                  type: MediaType.image,
                  url: 'https://example.com/tall.webp',
                  width: 800,
                  height: 1600,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('搜索结果点击打开帖子详情', (tester) async {
    await tester.pumpWidget(const LuntanApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('搜索帖子、用户、板块、榜单').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '大尺寸倒模');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SearchPostRow).first);
    await tester.pumpAndSettle();

    expect(find.byType(PostDetailScreen), findsOneWidget);
  });

  testWidgets('我的发布列表点击打开帖子详情', (tester) async {
    await tester.pumpWidget(const LuntanApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的发布').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('为啥很少朋友推荐星野爱丽丝2代？'));
    await tester.pumpAndSettle();

    expect(find.byType(PostDetailScreen), findsOneWidget);
  });

  testWidgets('我的评论按收到回复的帖子打开详情', (tester) async {
    await tester.pumpWidget(const LuntanApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的评论').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('为啥很少朋友推荐星野爱丽丝2代？').last);
    await tester.pumpAndSettle();

    expect(find.byType(PostDetailScreen), findsOneWidget);
  });
}
