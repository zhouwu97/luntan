import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/controllers/feed_controller.dart';
import 'package:luntan/controllers/interaction_controller.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/domain/repositories.dart';
import 'package:luntan/screens/home_screen.dart';

class _PagedHomeFeed implements FeedRepository, QueryableFeedRepository {
  _PagedHomeFeed(this.pages);

  final List<FeedPage> pages;
  final List<
    ({
      String? cursor,
      String? communityId,
      String sort,
      LatestOrder latestOrder,
    })
  >
  calls = [];

  @override
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20}) =>
      getFeed(cursor: cursor, limit: limit);

  @override
  Future<FeedPage> getFeed({
    String? cursor,
    int limit = 20,
    String? communityId,
    String sort = 'recommended',
    LatestOrder latestOrder = LatestOrder.comment,
    String? postType,
    bool? hasMedia,
    String? topic,
  }) async {
    calls.add((
      cursor: cursor,
      communityId: communityId,
      sort: sort,
      latestOrder: latestOrder,
    ));
    return pages[calls.length - 1];
  }
}

class _RecordingRecommendationRepository extends PlatformRepository {
  _RecordingRecommendationRepository()
    : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  bool setCalled = false;
  bool removeCalled = false;

  @override
  Future<void> setHomeRecommendation({
    required String postId,
    int? position,
    DateTime? expiresAt,
  }) async {
    setCalled = true;
  }

  @override
  Future<void> removeHomeRecommendation(String postId) async {
    removeCalled = true;
  }
}

Post _post(String id, {DateTime? activityAt, bool isRecommended = false}) =>
    Post(
      id: id,
      authorId: 'author-$id',
      communityId: 'community-unboxing',
      title: '自动分页帖子 $id',
      content: '用于验证首页在首屏没有滚动空间时会继续补充下一页。',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      activityAt: activityAt,
      lastCommentAt: activityAt,
      isRecommended: isRecommended,
    );

Widget _homeFor(
  FeedController controller,
  _PagedHomeFeed repository, {
  PlatformRepository? platform,
  bool canModerate = false,
}) {
  final store = ForumStore.uiOnly();
  return MaterialApp(
    home: HomeScreen(
      store: store,
      feedController: controller,
      feedRepository: repository,
      platform: platform,
      canModerate: canModerate,
      interactionController: InteractionController(
        repository: MockInteractionRepository(),
      ),
      isAuthenticated: false,
      onOpenPost: (_) {},
      onOpenComments: (_) {},
      onOpenProfile: () {},
      onOpenMessages: () {},
      onFeedback: (_) {},
      onToggleLike: (_) {},
      onToggleBookmark: (_) {},
      onRequireAuth: () {},
      onOpenPostId: (_) {},
    ),
  );
}

void main() {
  test('首页只按产品固定顺序展示三个正式板块', () {
    final communities = [
      const Community(
        id: 'community_qa',
        slug: 'qa',
        name: 'QA测试板块',
        description: '测试数据',
        categoryId: 'cat-qa',
        sortOrder: 0,
      ),
      const Community(
        id: 'community-daily',
        slug: 'daily',
        name: '杂鱼日常',
        description: '日常内容',
        categoryId: 'cat-life',
        sortOrder: 3,
      ),
      const Community(
        id: 'community-unboxing',
        slug: 'unboxing',
        name: '大型拆箱',
        description: '导入内容',
        categoryId: 'cat-import',
        sortOrder: 10,
      ),
      const Community(
        id: 'community-campus',
        slug: 'campus',
        name: '酱紫社区',
        description: '导入内容',
        categoryId: 'cat-import',
        sortOrder: 11,
      ),
    ];

    final visible = selectHomeCommunities(communities);

    expect(visible.map((item) => item.name), ['大型拆箱', '酱紫社区', '杂鱼日常']);
    expect(visible, isNot(contains(communities.first)));
  });

  test('首页识别服务端导入板块并排除 QA 板块', () {
    final visible = selectHomeCommunities([
      const Community(
        id: 'community_qa',
        slug: 'qa',
        name: 'QA测试板块',
        description: '测试数据',
        categoryId: 'cat-qa',
        sortOrder: 0,
      ),
      const Community(
        id: 'community-import-forum',
        slug: 'import-forum',
        name: '酱紫社区',
        description: '源站导入',
        categoryId: 'cat-import',
        sortOrder: 11,
        postCount: 100,
      ),
      const Community(
        id: 'community-import-daily',
        slug: 'import-daily',
        name: '杂鱼日常',
        description: '源站导入',
        categoryId: 'cat-import',
        sortOrder: 12,
        postCount: 3,
      ),
      const Community(
        id: 'community-import-unboxing',
        slug: 'import-unboxing',
        name: '大型拆箱',
        description: '源站导入',
        categoryId: 'cat-import',
        sortOrder: 10,
        postCount: 7,
      ),
    ]);

    expect(visible.map((item) => item.id), [
      'community-import-unboxing',
      'community-import-forum',
      'community-import-daily',
    ]);
    expect(visible.map((item) => item.id), isNot(contains('community_qa')));
  });

  testWidgets('API 首页默认最新并在首屏不足时最多自动补四页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pages = List<FeedPage>.generate(
      5,
      (index) => FeedPage(
        items: [_post('${index + 1}')],
        hasMore: true,
        nextCursor: 'cursor-${index + 1}',
      ),
    );
    final repository = _PagedHomeFeed(pages);
    final controller = FeedController(repository: repository);

    await tester.pumpWidget(_homeFor(controller, repository));
    await tester.pumpAndSettle();

    expect(find.text('综合'), findsNothing);
    expect(find.text('酱紫社区'), findsOneWidget);
    expect(repository.calls.first.sort, 'latest');
    expect(repository.calls.first.latestOrder, LatestOrder.post);
    expect(repository.calls, hasLength(5));
    expect(
      repository.calls.every((call) => call.communityId == 'community-campus'),
      isTrue,
    );
    expect(repository.calls.skip(1).map((call) => call.cursor), [
      'cursor-1',
      'cursor-2',
      'cursor-3',
      'cursor-4',
    ]);
  });

  testWidgets('最新排序下显示按回复与按发帖胶囊，无需登录即可切换', (tester) async {
    final pages = [
      FeedPage(
        items: [
          _post(
            '1',
            activityAt: DateTime.now().subtract(const Duration(minutes: 10)),
          ),
        ],
        hasMore: false,
      ),
      FeedPage(
        items: [
          _post(
            '2',
            activityAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ],
        hasMore: false,
      ),
      FeedPage(items: [_post('3')], hasMore: false),
    ];
    final repository = _PagedHomeFeed(pages);
    final controller = FeedController(repository: repository);

    await tester.pumpWidget(_homeFor(controller, repository));
    await tester.pumpAndSettle();

    // 首页默认就是最新，并默认按发帖时间排序。
    expect(find.text('按回复'), findsOneWidget);
    expect(find.text('按发帖'), findsOneWidget);
    expect(find.textContaining('最近回复'), findsNothing);

    // 切换到按回复后，服务端查询条件也随之变化。
    await tester.tap(find.text('按回复'));
    await tester.pumpAndSettle();
    expect(repository.calls.last.sort, 'latest');
    expect(repository.calls.last.latestOrder, LatestOrder.comment);
    expect(find.textContaining('最近回复'), findsOneWidget);

    // 再切回按发帖。
    await tester.tap(find.text('按发帖'));
    await tester.pumpAndSettle();

    expect(repository.calls.last.sort, 'latest');
    expect(repository.calls.last.latestOrder, LatestOrder.post);
  });

  testWidgets('管理员可以从帖子菜单加入或移出首页推荐', (tester) async {
    final repository = _PagedHomeFeed([
      FeedPage(items: [_post('p1', isRecommended: true)], hasMore: false),
      FeedPage(items: [_post('p1', isRecommended: true)], hasMore: false),
    ]);
    final platform = _RecordingRecommendationRepository();
    final controller = FeedController(repository: repository);

    await tester.pumpWidget(
      _homeFor(controller, repository, platform: platform, canModerate: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('移出首页推荐'), findsOneWidget);
    await tester.tap(find.text('移出首页推荐'));
    await tester.pumpAndSettle();

    expect(platform.removeCalled, isTrue);
  });
}
