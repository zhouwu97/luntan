import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/controllers/feed_controller.dart';
import 'package:luntan/controllers/home_personal_feed_controller.dart';
import 'package:luntan/controllers/interaction_controller.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/domain/repositories.dart';
import 'package:luntan/screens/home_screen.dart';

class _PagedHomeFeed implements FeedRepository, QueryableFeedRepository {
  _PagedHomeFeed(this.pages);

  final List<FeedPage> pages;
  final List<({String? cursor, String? communityId, String sort, LatestOrder latestOrder})> calls = [];

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
  }) async {
    calls.add((cursor: cursor, communityId: communityId, sort: sort, latestOrder: latestOrder));
    return pages[calls.length - 1];
  }
}

Post _post(String id, {DateTime? activityAt}) => Post(
  id: id,
  authorId: 'author-$id',
  communityId: 'community-unboxing',
  title: '自动分页帖子 $id',
  content: '用于验证首页在首屏没有滚动空间时会继续补充下一页。',
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
  activityAt: activityAt,
  lastCommentAt: activityAt,
);

Widget _homeFor(FeedController controller, _PagedHomeFeed repository) {
  final store = ForumStore.uiOnly();
  return MaterialApp(
    home: HomeScreen(
      store: store,
      feedController: controller,
      feedRepository: repository,
      personalFeedController: HomePersonalFeedController(mockStore: store),
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
  test('首页公开板块默认跳过 QA 测试板块并保留导入社区', () {
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
        id: 'community-import-unboxing',
        slug: 'import-unboxing',
        name: '大型拆箱',
        description: '导入内容',
        categoryId: 'cat-import',
        sortOrder: 10,
      ),
      const Community(
        id: 'community-import-forum',
        slug: 'import-forum',
        name: '酱紫社区',
        description: '导入内容',
        categoryId: 'cat-import',
        sortOrder: 11,
      ),
    ];

    final visible = selectHomeCommunities(communities);

    expect(visible.map((item) => item.name), ['大型拆箱', '酱紫社区']);
    expect(visible, isNot(contains(communities.first)));
  });

  testWidgets('API 首页默认综合流并在首屏不足时最多自动补四页', (tester) async {
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

    expect(find.text('综合'), findsOneWidget);
    expect(repository.calls, hasLength(5));
    expect(repository.calls.every((call) => call.communityId == null), isTrue);
    expect(
      repository.calls.skip(1).map((call) => call.cursor),
      ['cursor-1', 'cursor-2', 'cursor-3', 'cursor-4'],
    );
  });

  testWidgets('最新排序下显示按回复与按发帖胶囊，无需登录即可切换', (tester) async {
    final pages = [
      FeedPage(
        items: [_post('1', activityAt: DateTime.now().subtract(const Duration(minutes: 10)))],
        hasMore: false,
      ),
      FeedPage(
        items: [_post('2', activityAt: DateTime.now().subtract(const Duration(minutes: 5)))],
        hasMore: false,
      ),
      FeedPage(
        items: [_post('3')],
        hasMore: false,
      ),
    ];
    final repository = _PagedHomeFeed(pages);
    final controller = FeedController(repository: repository);

    await tester.pumpWidget(_homeFor(controller, repository));
    await tester.pumpAndSettle();

    // 默认在推荐 Tab，不显示右侧最新排序胶囊
    expect(find.text('按回复'), findsNothing);
    expect(find.text('按发帖'), findsNothing);

    // 点击「最新」Tab
    await tester.tap(find.text('最新'));
    await tester.pumpAndSettle();

    // 显示右侧胶囊，默认按回复
    expect(find.text('按回复'), findsOneWidget);
    expect(find.text('按发帖'), findsOneWidget);
    expect(find.textContaining('最近回复'), findsOneWidget);

    // 点击「按发帖」
    await tester.tap(find.text('按发帖'));
    await tester.pumpAndSettle();

    expect(repository.calls.last.sort, 'latest');
    expect(repository.calls.last.latestOrder, LatestOrder.post);
  });
}
