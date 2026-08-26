import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/controllers/feed_controller.dart';
import 'package:luntan/controllers/post_detail_controller.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/repository_provider.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/repositories.dart';

void main() {
  test('FeedController 支持初始加载、分页和重复 loadMore 防护', () async {
    final store = ForumStore.seeded();
    final controller = FeedController(
      repository: MockFeedRepository(store: store),
    );

    await controller.initialLoad();
    expect(controller.state.status, FeedStatus.success);
    expect(controller.state.items, hasLength(12));
    expect(controller.state.hasMore, isFalse);

    await controller.loadMore();
    expect(controller.state.items, hasLength(12));
  });

  test('FeedController 空数据进入 empty 状态', () async {
    final repository = _EmptyFeedRepository();
    final controller = FeedController(repository: repository);
    await controller.initialLoad();
    expect(controller.state.status, FeedStatus.empty);
  });

  test('应用 Mock 首页按页追加内容，触底后可以继续加载', () async {
    final repositories = ForumRepositories.mock();
    addTearDown(repositories.close);
    final controller = FeedController(repository: repositories.feed);

    await controller.setQuery(
      communityId: 'community-unboxing',
      sort: 'latest',
    );
    expect(controller.state.items, hasLength(3));
    expect(controller.state.hasMore, isTrue);

    await controller.loadMore();

    expect(controller.state.items, hasLength(5));
    expect(controller.state.hasMore, isFalse);
  });

  test('PostDetailController 区分成功和不存在', () async {
    final controller = PostDetailController(
      repository: MockPostRepository(),
      postId: 'u1',
    );
    await controller.load();
    expect(controller.state.status, PostDetailStatus.success);
    expect(controller.state.detail?.post.id, 'u1');

    final missing = PostDetailController(
      repository: MockPostRepository(),
      postId: 'missing',
    );
    await missing.load();
    expect(missing.state.status, PostDetailStatus.notFound);
  });
}

class _EmptyFeedRepository implements FeedRepository {
  @override
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20}) async =>
      const FeedPage(items: []);
}
