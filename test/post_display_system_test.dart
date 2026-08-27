import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/domain/models.dart';
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
    testWidgets('4. 单张 3:4 图片 Feed 不再固定裁成 240px，按比例自适应展开', (tester) async {
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
                    height: 400, // 3:4 ratio -> height = 360 / (3/4) = 480
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(PostMediaPreview));
      expect(size.height, greaterThan(350));
    });

    testWidgets('5. 极端长图展示底部提示', (tester) async {
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
                    width: 100,
                    height: 800, // ratio = 0.125
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('长图 · 点击查看完整图片'), findsOneWidget);
    });

    testWidgets('6. 两张图 Feed 采用纵向列表展示', (tester) async {
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
    });

    testWidgets('7. 详情页图片流纵向完整展示全部图片', (tester) async {
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
                      width: 400,
                      height: 300,
                    ),
                    MediaAsset(
                      id: 'd-2',
                      type: MediaType.image,
                      url: 'https://example.com/2.jpg',
                      width: 400,
                      height: 300,
                    ),
                    MediaAsset(
                      id: 'd-3',
                      type: MediaType.image,
                      url: 'https://example.com/3.jpg',
                      width: 400,
                      height: 300,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNWidgets(3));
    });

    testWidgets('8. 点击图片触发 onImageTap 并在对应 initialIndex 打开画廊', (tester) async {
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
