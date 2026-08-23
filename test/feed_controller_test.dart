import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/controllers/feed_controller.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/domain/repositories.dart';

class _RecordingFeed implements FeedRepository, QueryableFeedRepository {
  _RecordingFeed(this.pages);

  final List<FeedPage> pages;
  final List<({String? cursor, String? communityId, String sort})> calls = [];
  int index = 0;

  @override
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20}) =>
      getFeed(cursor: cursor, limit: limit);

  @override
  Future<FeedPage> getFeed({
    String? cursor,
    int limit = 20,
    String? communityId,
    String sort = 'recommended',
  }) {
    calls.add((cursor: cursor, communityId: communityId, sort: sort));
    final page = pages[index < pages.length ? index : pages.length - 1];
    index += 1;
    return Future.value(page);
  }
}

Post _post(String id, String communityId) => Post(
      id: id,
      authorId: 'author-1',
      communityId: communityId,
      title: 'title',
      content: 'content',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  test('setQuery 切换板块/排序时清空旧内容并透传参数', () async {
    final feed = _RecordingFeed([
      FeedPage(items: [_post('a', 'campus')], hasMore: true, nextCursor: 'p1'),
      FeedPage(items: [_post('b', 'gaming')]),
    ]);
    final controller = FeedController(repository: feed);

    await controller.initialLoad();
    expect(controller.state.items.map((post) => post.id), ['a']);

    await controller.setQuery(communityId: 'gaming', sort: 'latest');
    expect(feed.calls.last.communityId, 'gaming');
    expect(feed.calls.last.sort, 'latest');
    expect(controller.state.items.map((post) => post.id), ['b']);
  });

  test('相同查询不重复加载', () async {
    final feed = _RecordingFeed([
      FeedPage(items: [_post('a', 'campus')], hasMore: true, nextCursor: 'p1'),
      FeedPage(items: [_post('b', 'campus')]),
    ]);
    final controller = FeedController(repository: feed);

    await controller.initialLoad();
    await controller.setQuery(communityId: null, sort: 'recommended');

    expect(feed.calls, hasLength(1));
  });

  test('applyDetailResult 把详情页状态增量同步回列表', () async {
    final initial = Post(
      id: 'a',
      authorId: 'author-1',
      communityId: 'campus',
      title: 'old title',
      content: 'old content',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final feed = _RecordingFeed([
      FeedPage(items: [initial], hasMore: false),
    ]);
    final controller = FeedController(repository: feed);
    await controller.initialLoad();

    final detail = Post(
      id: 'a',
      authorId: 'author-1',
      communityId: 'campus',
      title: 'new title',
      content: 'new content',
      commentCount: 3,
      likeCount: 7,
      bookmarkCount: 2,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      viewerState: ViewerPostState(hasLiked: true, hasBookmarked: true),
    )..isLiked = true;

    controller.applyDetailResult(detail);
    final synced = controller.state.items.single;
    expect(synced.isLiked, isTrue);
    expect(synced.title, 'new title');
    expect(synced.likeCount, 7);
    expect(synced.commentCount, 3);
    expect(feed.calls, hasLength(1), reason: '增量同步不应触发新的网络请求');
  });

  test('loadMore 按 id 去重追加', () async {
    final feed = _RecordingFeed([
      FeedPage(items: [_post('a', 'x'), _post('b', 'x')], hasMore: true, nextCursor: 'c1'),
      FeedPage(items: [_post('b', 'x'), _post('c', 'x')]),
    ]);
    final controller = FeedController(repository: feed);

    await controller.initialLoad();
    await controller.loadMore();

    expect(controller.state.items.map((post) => post.id), ['a', 'b', 'c']);
    expect(controller.state.hasMore, isFalse);
  });
}