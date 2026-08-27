import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/auth_repository.dart';
import 'package:luntan/data/api/profile_repository.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/screens/entity_screens.dart';
import 'package:luntan/screens/profile_screen.dart';

class _MockProfileRepo extends ProfileRepository {
  _MockProfileRepo({
    required this.summary,
    this.posts = const [],
    this.comments = const [],
  }) : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  final ProfileSummary summary;
  final List<ProfilePostItem> posts;
  final List<ProfilePostItem> comments;

  @override
  Future<ProfileSummary> getProfile() async => summary;

  @override
  Future<ProfileListPage> list(
    String kind, {
    String? cursor,
    int limit = 20,
    bool includeDetails = false,
  }) async {
    if (kind == 'comments') {
      return ProfileListPage(items: comments);
    }
    return ProfileListPage(items: posts);
  }
}

void main() {
  group('Profile 一致性与游客架构测试', () {
    testWidgets('1. 新游客在 API 模式下显示 Lv.0、合并游客提示、空发布引导', (tester) async {
      var authRequested = 0;
      const guestSummary = ProfileSummary(
        id: 'guest_user_1',
        username: 'guest_9527',
        nickname: '游客9527',
        level: 0,
        experience: 0,
        growth: GrowthState(
          level: 0,
          experience: 0,
          levelStartExperience: 0,
          nextLevelExperience: 1000,
          experienceInLevel: 0,
          experienceRequiredInLevel: 1000,
          progress: 0.0,
          levelLocked: true,
        ),
        trustLevel: 'new',
        signature: '',
        postCount: 0,
        commentCount: 0,
        likeReceivedCount: 0,
        followerCount: 0,
        followingCount: 0,
      );

      final repo = _MockProfileRepo(summary: guestSummary);

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            store: ForumStore.uiOnly(),
            isApiMode: true,
            profileRepository: repo,
            currentUser: const AuthUser(
              id: 'guest_user_1',
              username: 'guest_9527',
              nickname: '游客9527',
              level: 0,
              status: 'active',
              accountType: 'guest',
            ),
            currentUserId: 'guest_user_1',
            onOpenPost: (_) {},
            onOpenHome: () {},
            onOpenComposer: () {},
            onOpenMessages: () {},
            onFeedback: (_) {},
            onRequireAuth: () => authRequested++,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 验证游客权威等级
      expect(find.text('@guest_9527 · Lv.0 · 信任 new'), findsOneWidget);
      // 验证合并游客提示横条
      expect(find.text('游客模式 · 当前累计 0 EXP'), findsOneWidget);
      expect(find.text('注册邮箱账号后保留当前经验与评论，并解锁等级和发布'), findsOneWidget);

      // 验证无发布内容空状态
      expect(find.text('暂时没有发布内容'), findsOneWidget);
      expect(find.text('游客可以浏览和评论，注册邮箱账号后即可发布帖子。'), findsOneWidget);
      // 杜绝设计备注文案泄漏
      expect(find.textContaining('空状态只保留一个明确动作'), findsNothing);

      // postCount == 0 时隐藏"查看全部"
      expect(find.text('查看全部'), findsNothing);

      // 验证合并卡片内登录/注册按钮
      await tester.tap(find.text('登录 / 注册').last);
      expect(authRequested, 1);
    });

    testWidgets('2. 个人主页入口为真实单入口且导航到 UserProfileScreen', (tester) async {
      const summary = ProfileSummary(
        id: 'user_100',
        username: 'cup_master',
        nickname: '杯友老张',
        level: 3,
        experience: 2400,
        growth: GrowthState(
          level: 3,
          experience: 2400,
          levelStartExperience: 2000,
          nextLevelExperience: 3000,
          experienceInLevel: 400,
          experienceRequiredInLevel: 1000,
          progress: 0.4,
          levelLocked: false,
        ),
        trustLevel: 'trusted',
        signature: '评测老手',
        postCount: 1,
        commentCount: 2,
        likeReceivedCount: 10,
        followerCount: 5,
        followingCount: 3,
      );

      final repo = _MockProfileRepo(
        summary: summary,
        posts: [
          ProfilePostItem(
            id: 'post_1001',
            authorId: 'user_100',
            communityId: 'c1',
            communityName: '评测专区',
            title: '真实开箱体验分享',
            contentPreview: '做工非常精致',
            publishedAt: DateTime.now(),
            commentCount: 5,
            likeCount: 2,
            bookmarkCount: 1,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            store: ForumStore.uiOnly(),
            isApiMode: true,
            profileRepository: repo,
            currentUser: const AuthUser(
              id: 'user_100',
              username: 'cup_master',
              nickname: '杯友老张',
              level: 3,
              status: 'active',
              accountType: 'email',
            ),
            currentUserId: 'user_100',
            onOpenPost: (_) {},
            onOpenHome: () {},
            onOpenComposer: () {},
            onOpenMessages: () {},
            onFeedback: (_) {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 单一入口
      expect(find.text('个人主页'), findsOneWidget);

      // 点击进入个人主页
      await tester.tap(find.text('个人主页'));
      await tester.pumpAndSettle();

      // 真实导航到 UserProfileScreen
      expect(find.byType(UserProfileScreen), findsOneWidget);
      expect(find.text('编辑资料'), findsOneWidget);
      expect(find.text('杯友老张'), findsOneWidget);
    });

    testWidgets('3. 我的评论列表展示评论正文、原帖标题并带 focusCommentId 跳转', (tester) async {
      String? openedPostId;
      String? focusedCommentId;

      const summary = ProfileSummary(
        id: 'user_100',
        username: 'cup_master',
        nickname: '杯友老张',
        level: 1,
        trustLevel: 'new',
        signature: '',
        postCount: 0,
        commentCount: 1,
        likeReceivedCount: 0,
        followerCount: 0,
        followingCount: 0,
      );

      final repo = _MockProfileRepo(
        summary: summary,
        comments: [
          ProfilePostItem(
            id: 'post_200',
            commentId: 'comment_999',
            authorId: 'user_100',
            communityId: 'c1',
            communityName: '日常区',
            title: '这是原帖的标题',
            contentPreview: '这是我发表的精彩评论内容',
            publishedAt: DateTime.now().subtract(const Duration(minutes: 5)),
            activityAt: DateTime.now().subtract(const Duration(minutes: 5)),
            commentCount: 0,
            likeCount: 0,
            bookmarkCount: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            store: ForumStore.uiOnly(),
            isApiMode: true,
            profileRepository: repo,
            currentUser: const AuthUser(
              id: 'user_100',
              username: 'cup_master',
              nickname: '杯友老张',
              level: 1,
              status: 'active',
              accountType: 'email',
            ),
            currentUserId: 'user_100',
            onOpenPost: (_) {},
            onOpenPostById: (id, {focusComments, focusCommentId}) {
              openedPostId = id;
              focusedCommentId = focusCommentId;
            },
            onOpenHome: () {},
            onOpenComposer: () {},
            onOpenMessages: () {},
            onFeedback: (_) {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 点击"我的评论"指标打开弹窗 Sheet
      await tester.tap(find.text('我的评论'));
      await tester.pumpAndSettle();

      // 验证评论展示（使用中文弯引号 \u201C \u201D）
      expect(find.text('\u201c这是我发表的精彩评论内容\u201d'), findsOneWidget);
      expect(find.text('回复于《这是原帖的标题》'), findsOneWidget);

      // 点击该条目，验证携带 focusCommentId 跳转
      await tester.tap(find.text('\u201c这是我发表的精彩评论内容\u201d'));
      await tester.pumpAndSettle();

      expect(openedPostId, 'post_200');
      expect(focusedCommentId, 'comment_999');
    });

    testWidgets('4. 游客点击收藏/点赞直接引导登录注册', (tester) async {
      var authTriggered = 0;
      const guestSummary = ProfileSummary(
        id: 'guest_1',
        username: 'guest_1',
        nickname: '游客1',
        level: 0,
        trustLevel: 'new',
        signature: '',
        postCount: 0,
        commentCount: 0,
        likeReceivedCount: 0,
        followerCount: 0,
        followingCount: 0,
      );

      final repo = _MockProfileRepo(summary: guestSummary);

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            store: ForumStore.uiOnly(),
            isApiMode: true,
            profileRepository: repo,
            currentUser: const AuthUser(
              id: 'guest_1',
              username: 'guest_1',
              nickname: '游客1',
              level: 0,
              status: 'active',
              accountType: 'guest',
            ),
            currentUserId: 'guest_1',
            onOpenPost: (_) {},
            onOpenHome: () {},
            onOpenComposer: () {},
            onOpenMessages: () {},
            onFeedback: (_) {},
            onRequireAuth: () => authTriggered++,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 游客点击我的收藏 → 引导登录
      await tester.tap(find.text('我的收藏'));
      expect(authTriggered, 1);

      // 游客点击我的点赞 → 引导登录
      await tester.tap(find.text('我的点赞'));
      expect(authTriggered, 2);
    });
  });
}
