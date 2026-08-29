import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/widgets/app_network_image.dart';
import 'package:luntan/widgets/comments/comment_reply_bar.dart';
import 'package:luntan/widgets/forum_author_row.dart';
import 'package:luntan/widgets/forum_post_card.dart';
import 'package:luntan/widgets/post_media_preview.dart';

void main() {
  final now = DateTime.now();

  group('一、ForumAuthorRow 作者行与等级测试', () {
    testWidgets('1. 有头像时 ForumAuthorRow 渲染网络头像', (tester) async {
      final post = Post(
        id: 'post-1',
        authorId: 'u1',
        communityId: 'c1',
        author: User(
          id: 'u1',
          username: 'tester',
          nickname: '测试用户',
          avatar: 'https://example.com/avatar.png',
          level: 3,
          createdAt: now,
          updatedAt: now,
        ),
        title: '测试标题',
        content: '测试内容',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ForumAuthorRow(post: post),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('测试用户'), findsOneWidget);
      expect(find.text('Lv.3'), findsOneWidget);
    });

    testWidgets('2. 无头像时 ForumAuthorRow fallback 昵称首字符', (tester) async {
      final post = Post(
        id: 'post-2',
        authorId: 'u2',
        communityId: 'c1',
        author: User(
          id: 'u2',
          username: 'tester2',
          nickname: '夜猫试用员',
          avatar: null,
          level: 5,
          createdAt: now,
          updatedAt: now,
        ),
        title: '测试标题',
        content: '测试内容',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ForumAuthorRow(post: post),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('夜'), findsOneWidget);
      expect(find.text('Lv.5'), findsOneWidget);
    });

    testWidgets('3. 游客或匿名作者显示 Lv.0', (tester) async {
      final guestPost = Post(
        id: 'post-guest',
        authorId: 'guest-12345',
        communityId: 'c1',
        author: null,
        title: '游客帖子',
        content: '游客内容',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ForumAuthorRow(post: guestPost),
          ),
        ),
      );

      expect(find.text('Lv.0'), findsOneWidget);
      expect(find.text('游客'), findsOneWidget);
    });
  });

  group('二、图片系统与多图流测试', () {
    testWidgets('4. 单张 3:4 图片 Feed 不再固定裁成 240px，按比例自适应展开 (480px) 且不出现长图标签', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: PostMediaPreview(
                images: [
                  MediaAsset(
                    id: 'img-3-4',
                    type: MediaType.image,
                    url: 'https://example.com/3_4.jpg',
                    width: 300,
                    height: 400, // 3:4 ratio -> 0.75 in [0.72, 1.78] -> height = 360 / 0.75 = 480
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(PostMediaPreview));
      // 480 + 10 top padding = 490
      expect(size.height, closeTo(490, 1.0));
      expect(find.text('长图'), findsNothing);
    });

    testWidgets('5. 9:16 长图与 1:2 极长图 Feed 钳制到 0.72 (500px) 且展示顶部对齐与轻量长图角标', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: PostMediaPreview(
                images: [
                  MediaAsset(
                    id: 'img-long',
                    type: MediaType.image,
                    url: 'https://example.com/long.jpg',
                    width: 90,
                    height: 160, // 9:16 ratio = 0.5625 < 0.72 -> clamped to 0.72 -> height = 360 / 0.72 = 500
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(PostMediaPreview));
      // 500 + 10 top padding = 510
      expect(size.height, closeTo(510, 1.0));
      expect(find.text('长图'), findsOneWidget);

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.alignment, Alignment.topCenter);
    });

    testWidgets('6. 两张图 Feed 采用左右双列拼图', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: PostMediaPreview(
                images: [
                  MediaAsset(
                    id: 'img-1',
                    type: MediaType.image,
                    url: 'https://example.com/1.jpg',
                    width: 400,
                    height: 300,
                  ),
                  MediaAsset(
                    id: 'img-2',
                    type: MediaType.image,
                    url: 'https://example.com/2.jpg',
                    width: 400,
                    height: 300,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNWidgets(2));
      final size = tester.getSize(find.byType(PostMediaPreview));
      // 宽度 360，(360-6)/2 * 0.95 ≈ 168.15 + 10 top padding = 178.15
      expect(size.height, closeTo(178, 5.0));
    });

    testWidgets('7. 3张图与4+图 Feed 采用拼图与 +N 角标', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: PostMediaPreview(
                images: [
                  MediaAsset(id: '1', type: MediaType.image, url: '1.jpg', width: 400, height: 300),
                  MediaAsset(id: '2', type: MediaType.image, url: '2.jpg', width: 400, height: 300),
                  MediaAsset(id: '3', type: MediaType.image, url: '3.jpg', width: 400, height: 300),
                  MediaAsset(id: '4', type: MediaType.image, url: '4.jpg', width: 400, height: 300),
                  MediaAsset(id: '5', type: MediaType.image, url: '5.jpg', width: 400, height: 300),
                  MediaAsset(id: '6', type: MediaType.image, url: '6.jpg', width: 400, height: 300),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AppNetworkImage), findsNWidgets(4));
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('8. 详情页图片流纵向完整展示全部图片且不限高', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: PostMediaPreview(
                  mode: PostMediaPreviewMode.detail,
                  images: [
                    MediaAsset(
                      id: 'd-1',
                      type: MediaType.image,
                      url: 'https://example.com/1.jpg',
                      width: 360,
                      height: 720, // 1:2 -> height = 720
                    ),
                    MediaAsset(
                      id: 'd-2',
                      type: MediaType.image,
                      url: 'https://example.com/2.jpg',
                      width: 360,
                      height: 360, // 1:1 -> height = 360
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNWidgets(2));
      final size = tester.getSize(find.byType(PostMediaPreview));
      // 720 + 360 + padding/spacing 12 + 10 = 1102
      expect(size.height, closeTo(1102, 10.0));
    });

    testWidgets('9. 点击图片触发 onImageTap 并在对应 initialIndex 打开画廊', (tester) async {
      int? tappedIndex;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: PostMediaPreview(
                images: const [
                  MediaAsset(
                    id: 't-1',
                    type: MediaType.image,
                    url: 'https://example.com/1.jpg',
                    width: 400,
                    height: 300,
                  ),
                  MediaAsset(
                    id: 't-2',
                    type: MediaType.image,
                    url: 'https://example.com/2.jpg',
                    width: 400,
                    height: 300,
                  ),
                ],
                onImageTap: (index) => tappedIndex = index,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Image).at(1));
      expect(tappedIndex, equals(1));
    });

    testWidgets('10. 针对 16:9, 4:3, 1:1, 4:5, 3:4, 2:3, 9:16, 1:2 验收 Feed 比例钳制与 Detail 真实展开', (tester) async {
      // 验收比例列表: [width, height, expectedFeedHeight, expectLongBadge]
      final cases = [
        {'w': 1600, 'h': 900, 'feedH': 360.0 / 1.7777777777777777, 'badge': false}, // 16:9 -> ~202.5
        {'w': 400, 'h': 300, 'feedH': 360.0 / (4.0 / 3.0), 'badge': false},           // 4:3 -> 270
        {'w': 300, 'h': 300, 'feedH': 360.0, 'badge': false},                          // 1:1 -> 360
        {'w': 400, 'h': 500, 'feedH': 360.0 / 0.8, 'badge': false},                   // 4:5 -> 450
        {'w': 300, 'h': 400, 'feedH': 360.0 / 0.75, 'badge': false},                  // 3:4 -> 480
        {'w': 200, 'h': 300, 'feedH': 360.0 / 0.72, 'badge': true},                   // 2:3 (0.667 < 0.72) -> 500
        {'w': 90, 'h': 160, 'feedH': 360.0 / 0.72, 'badge': true},                    // 9:16 (0.5625) -> 500
        {'w': 100, 'h': 200, 'feedH': 360.0 / 0.72, 'badge': true},                   // 1:2 (0.50) -> 500
      ];

      for (final c in cases) {
        final w = c['w'] as int;
        final h = c['h'] as int;
        final expectedFeedH = c['feedH'] as double;
        final expectBadge = c['badge'] as bool;

        // 验证 Feed
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: PostMediaPreview(
                  images: [
                    MediaAsset(
                      id: 'test-$w-$h',
                      type: MediaType.image,
                      url: 'https://example.com/$w-$h.jpg',
                      width: w,
                      height: h,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final feedSize = tester.getSize(find.byType(PostMediaPreview));
        // Feed 包含 top: 10 padding
        expect(feedSize.height, closeTo(expectedFeedH + 10.0, 1.0));
        if (expectBadge) {
          expect(find.text('长图'), findsOneWidget, reason: 'Ratio $w/$h should show badge');
        } else {
          expect(find.text('长图'), findsNothing, reason: 'Ratio $w/$h should not show badge');
        }

        // 验证 Detail (真实比例)
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 360,
                  child: PostMediaPreview(
                    mode: PostMediaPreviewMode.detail,
                    images: [
                      MediaAsset(
                        id: 'detail-$w-$h',
                        type: MediaType.image,
                        url: 'https://example.com/$w-$h.jpg',
                        width: w,
                        height: h,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final detailSize = tester.getSize(find.byType(PostMediaPreview));
        final expectedDetailH = 360.0 / (w / h) + 12.0; // padding top 12
        expect(detailSize.height, closeTo(expectedDetailH, 2.0));
      }
    });
  });

  group('三、ForumPostCard 与评论互动逻辑', () {
    testWidgets('9. commentCount=0 点击评论按钮依然触发 onOpenComments', (tester) async {
      var openedComments = false;
      final zeroCommentPost = Post(
        id: 'post-zero',
        authorId: 'u1',
        communityId: 'c1',
        title: '0评论帖子',
        content: '正文内容',
        commentCount: 0,
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ForumPostCard(
              post: zeroCommentPost,
              onOpen: () {},
              onOpenComments: () => openedComments = true,
              onLike: () {},
              onBookmark: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      expect(openedComments, isTrue);
    });
  });

  group('四、详情页 CommentReplyBar 双态互动栏测试', () {
    testWidgets('10. 默认态展示快捷入口与点赞/收藏状态，点击点赞触发回调', (tester) async {
      var liked = false;
      var bookmarked = false;
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: CommentReplyBar(
              controller: controller,
              commentCount: 15,
              likeCount: 42,
              isLiked: false,
              isBookmarked: false,
              blockedMessage: '你已被禁言',
              onFeedback: (_) {},
              onCancelTarget: () {},
              onSubmit: () {},
              onToggleLike: () => liked = true,
              onToggleBookmark: () => bookmarked = true,
            ),
          ),
        ),
      );

      expect(find.text('友善地回复一句…'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      expect(liked, isTrue);

      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      expect(bookmarked, isTrue);
    });

    testWidgets('11. 禁言用户点击伪输入框触发即时反馈提示', (tester) async {
      String? feedbackMessage;
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: CommentReplyBar(
              controller: controller,
              canComment: false,
              commentCount: 0,
              likeCount: 0,
              blockedMessage: '你已被禁言至 2026-10-01',
              onFeedback: (msg) => feedbackMessage = msg,
              onCancelTarget: () {},
              onSubmit: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('友善地回复一句…'));
      expect(feedbackMessage, equals('你已被禁言至 2026-10-01'));
    });

    testWidgets('12. 设置 replyTarget 后展示回复 @xxx 并可取消', (tester) async {
      var cancelled = false;
      final controller = TextEditingController();
      final targetComment = Comment(
        id: 'c1',
        postId: 'p1',
        authorId: 'u2',
        author: User(
          id: 'u2',
          username: 'alice',
          nickname: '爱丽丝',
          createdAt: now,
          updatedAt: now,
        ),
        content: '根评论内容',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: CommentReplyBar(
              controller: controller,
              target: targetComment,
              blockedMessage: '你已被禁言',
              onFeedback: (_) {},
              onCancelTarget: () => cancelled = true,
              onSubmit: () {},
            ),
          ),
        ),
      );

      expect(find.text('回复 @爱丽丝'), findsOneWidget);
      expect(find.text('发送'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(cancelled, isTrue);
    });
  });
}
