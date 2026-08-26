import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/controllers/feed_controller.dart';
import 'package:luntan/controllers/home_personal_feed_controller.dart';
import 'package:luntan/controllers/interaction_controller.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/repositories.dart';
import 'package:luntan/screens/home_screen.dart';

class _PagedHomeFeed implements FeedRepository, QueryableFeedRepository {
  _PagedHomeFeed(this.pages);

  final List<FeedPage> pages;
  final List<({String? cursor, String? communityId, String sort})> calls = [];

  @override
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20}) =>
      getFeed(cursor: cursor, limit: limit);

  @override
  Future<FeedPage> getFeed({
    String? cursor,
    int limit = 20,
    String? communityId,
    String sort = 'recommended',
    String? postType,
    bool? hasMedia,
  }) async {
    calls.add((cursor: cursor, communityId: communityId, sort: sort));
    return pages[calls.length - 1];
  }
}

Post _post(String id) => Post(
  id: id,
  authorId: 'author-$id',
  communityId: 'community-unboxing',
  title: '自动分页帖子 $id',
  content: '用于验证首页在首屏没有滚动空间时会继续补充下一页。',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
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
}
