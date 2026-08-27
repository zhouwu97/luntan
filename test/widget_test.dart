import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/app.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/auth_repository.dart';
import 'package:luntan/data/api/profile_repository.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/screens/post_detail_screen.dart';
import 'package:luntan/screens/governance_screens.dart';
import 'package:luntan/screens/profile_screen.dart';
import 'package:luntan/screens/settings_screen.dart';
import 'package:luntan/widgets/comments/comment_item.dart';
import 'package:luntan/widgets/forum_post_card.dart';
import 'package:luntan/widgets/post_media_preview.dart';
import 'package:luntan/widgets/search/search_post_row.dart';

class _CountingProfileRepository extends ProfileRepository {
  _CountingProfileRepository()
    : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  int calls = 0;

  @override
  Future<ProfileSummary> getProfile() async {
    calls++;
    return const ProfileSummary(
      id: 'user-1',
      username: 'email_user',
      nickname: '邮箱用户',
      level: 1,
      trustLevel: '普通',
      signature: '',
      postCount: 0,
      commentCount: 0,
      likeReceivedCount: 0,
      followerCount: 0,
      followingCount: 0,
    );
  }
}

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
          body: SingleChildScrollView(
            child: ForumPostCard(
              post: postWithImage,
              onOpen: () => opened = true,
              onOpenComments: () {},
              onLike: () {},
              onBookmark: () {},
              onMenu: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PostMediaPreview).first);

    expect(opened, isTrue);
  });

  testWidgets('零回复帖子点击回复仍会跳转到详情并聚焦评论', (tester) async {
    var openedComments = false;
    final post = ForumStore.seeded().posts.first;
    post.commentCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumPostCard(
            post: post,
            onOpen: () {},
            onOpenComments: () => openedComments = true,
            onLike: () {},
            onBookmark: () {},
            onMenu: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    expect(openedComments, isTrue);
  });

  testWidgets('帖子媒体缩略图居中裁切且不压扁', (tester) async {
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
    expect(image.fit, BoxFit.cover);
    // 解码只约束目标宽度，避免把容器的横向比例错误传给图片解码器。
    final provider = image.image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).height, isNull);
  });

  testWidgets('帖子详情媒体预览允许竖图使用更高的 detail 区域', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: PostMediaPreview(
                mode: PostMediaPreviewMode.detail,
                images: [
                  MediaAsset(
                    id: 'detail-tall-image',
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
      ),
    );

    expect(
      tester.getSize(find.byType(PostMediaPreview)).height,
      greaterThan(240),
    );
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
  });

  testWidgets('多图预览使用等比例裁切填充网格', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostMediaPreview(
              images: [
                MediaAsset(
                  id: 'grid-1',
                  type: MediaType.image,
                  url: 'https://example.com/1.jpg',
                  width: 800,
                  height: 1200,
                ),
                MediaAsset(
                  id: 'grid-2',
                  type: MediaType.image,
                  url: 'https://example.com/2.jpg',
                  width: 1200,
                  height: 800,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images, isNotEmpty);
    expect(images.every((image) => image.fit == BoxFit.cover), isTrue);
  });

  testWidgets('原图按钮只在图片详情页出现并可切换原图', (tester) async {
    const image = MediaAsset(
      id: 'original-image',
      type: MediaType.image,
      width: 1200,
      height: 1600,
      detail: MediaVariant(
        url: 'https://example.com/detail.jpg',
        width: 1200,
        height: 1600,
      ),
      original: MediaVariant(
        url: 'https://example.com/original.jpg',
        width: 2400,
        height: 3200,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: MediaGalleryScreen(images: [image])),
    );
    await tester.pumpAndSettle();

    expect(find.text('查看原图'), findsOneWidget);
    final detailProvider =
        tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(
      (detailProvider.imageProvider as NetworkImage).url,
      'https://example.com/detail.jpg',
    );
    await tester.tap(find.text('查看原图'));
    await tester.pumpAndSettle();

    expect(find.text('查看原图'), findsNothing);
    final originalProvider =
        tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(
      (originalProvider.imageProvider as NetworkImage).url,
      'https://example.com/original.jpg',
    );
  });

  testWidgets('游客个人中心提供登录和绑定邮箱入口', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          store: ForumStore.uiOnly(),
          currentUserId: null,
          isApiMode: true,
          onOpenPost: (_) {},
          onOpenHome: () {},
          onOpenComposer: () {},
          onOpenMessages: () {},
          onFeedback: (_) {},
          onRequireAuth: () => opened++,
        ),
      ),
    );

    expect(find.text('当前为游客模式'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    await tester.tap(find.text('去登录'));
    expect(opened, 1);
  });

  testWidgets('认证页返回后个人中心会重新请求资料', (tester) async {
    final repository = _CountingProfileRepository();
    const user = AuthUser(
      id: 'user-1',
      username: 'email_user',
      nickname: '邮箱用户',
      level: 1,
      status: 'active',
    );

    Widget buildProfile(int refreshToken) => MaterialApp(
      home: ProfileScreen(
        store: ForumStore.uiOnly(),
        currentUser: user,
        currentUserId: user.id,
        isApiMode: true,
        profileRepository: repository,
        refreshToken: refreshToken,
        onOpenPost: (_) {},
        onOpenHome: () {},
        onOpenComposer: () {},
        onOpenMessages: () {},
        onFeedback: (_) {},
      ),
    );

    await tester.pumpWidget(buildProfile(0));
    await tester.pumpAndSettle();
    expect(repository.calls, 1);

    await tester.pumpWidget(buildProfile(1));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
  });

  testWidgets('设置中心展示账号、通知、隐私和数据管理入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsCenterScreen(
          isGuest: true,
          onOpenMessages: () {},
          onFeedback: (_) {},
          onRequireAuth: () {},
          onClearHistory: () async {},
          onLogout: () async {},
          onDeleteAccount: () async {},
        ),
      ),
    );

    expect(find.text('登录 / 绑定邮箱'), findsOneWidget);
    expect(find.text('通知中心'), findsOneWidget);
    expect(find.text('隐私与安全'), findsOneWidget);
    expect(find.text('清空浏览历史'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('注销账号'), findsOneWidget);
  });

  testWidgets('治理中心只展示当前 capability 对应的入口', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: GovernanceCenterScreen(onOpenLogs: () => opened = true),
      ),
    );

    expect(find.text('治理中心'), findsOneWidget);
    expect(find.text('操作日志'), findsOneWidget);
    expect(find.text('管理员管理'), findsNothing);
    await tester.tap(find.text('操作日志'));
    expect(opened, isTrue);
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
