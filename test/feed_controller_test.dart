import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/controllers/feed_controller.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/domain/repositories.dart';

class _RecordingFeed implements FeedRepository, QueryableFeedRepository {
  _RecordingFeed(this.pages);

  final List<FeedPage> pages;
  final List<({String? cursor, String? communityId, String sort, LatestOrder latestOrder})> calls = [];
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
    LatestOrder latestOrder = LatestOrder.comment,
    String? postType,
    bool? hasMedia,
    String? topic,
  }) {
    calls.add((cursor: cursor, communityId: communityId, sort: sort, latestOrder: latestOrder));
    final page = pages[index < pages.length ? index : pages.length - 1];
    index += 1;
    return Future.value(page);
  }
}

class _PendingFeedRequest {
  _PendingFeedRequest({required this.communityId, required this.cursor});

  final String? communityId;
  final String? cursor;
  final Completer<FeedPage> completer = Completer<FeedPage>();
}

class _PendingFeed implements FeedRepository, QueryableFeedRepository {
  final List<_PendingFeedRequest> requests = <_PendingFeedRequest>[];

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
  }) {
    final request = _PendingFeedRequest(
      communityId: communityId,
      cursor: cursor,
    );
    requests.add(request);
    return request.completer.future;
  }
}

class _FailingLoadMoreFeed implements FeedRepository, QueryableFeedRepository {
  final List<String?> cursors = <String?>[];

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
  }) {
    cursors.add(cursor);
    if (cursor == null) {
      return Future.value(
        FeedPage(
          items: [_post('first', 'campus')],
          hasMore: true,
          nextCursor: 'page-2',
        ),
      );
    }
    return Future.error(StateError('模拟下一页网络失败'));
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
  test('setQuery 切换板块/排序与 LatestOrder 时清空旧内容并透传参数', () async {
    final feed = _RecordingFeed([
      FeedPage(items: [_post('a', 'campus')], hasMore: true, nextCursor: 'p1'),
      FeedPage(items: [_post('b', 'gaming')]),
      FeedPage(items: [_post('c', 'gaming')]),
    ]);
    final controller = FeedController(repository: feed);

    await controller.initialLoad();
    expect(controller.state.items.map((post) => post.id), ['a']);

    await controller.setQuery(communityId: 'gaming', sort: 'latest', latestOrder: LatestOrder.comment);
    expect(feed.calls.last.communityId, 'gaming');
    expect(feed.calls.last.sort, 'latest');
    expect(feed.calls.last.latestOrder, LatestOrder.comment);
    expect(controller.state.items.map((post) => post.id), ['b']);

    await controller.setLatestOrder(LatestOrder.post);
    expect(feed.calls.last.sort, 'latest');
    expect(feed.calls.last.latestOrder, LatestOrder.post);
    expect(controller.state.items.map((post) => post.id), ['c']);
  });

  test('相同查询不重复加载', () async {
    final feed = _RecordingFeed([
      FeedPage(items: [_post('a', 'campus')], hasMore: true, nextCursor: 'p1'),
      FeedPage(items: [_post('b', 'campus')]),
    ]);
    final controller = FeedController(repository: feed);

    await controller.initialLoad();
    await controller.setQuery(communityId: null, sort: 'recommended', latestOrder: LatestOrder.comment);

    expect(feed.calls, hasLength(1));
  });

  test('乱序完成的旧板块请求不能覆盖最后一次选择', () async {
    final feed = _PendingFeed();
    final controller = FeedController(repository: feed);

    final first = controller.setQuery(communityId: 'campus');
    final second = controller.setQuery(communityId: 'gaming');
    expect(feed.requests.map((request) => request.communityId), [
      'campus',
      'gaming',
    ]);

    feed.requests[1].completer.complete(
      FeedPage(items: [_post('gaming-post', 'gaming')]),
    );
    await second;
    expect(controller.state.items.single.id, 'gaming-post');

    feed.requests[0].completer.complete(
      FeedPage(items: [_post('campus-post', 'campus')]),
    );
    await first;
    expect(
      controller.state.items.single.id,
      'gaming-post',
      reason: '旧请求晚返回时不得覆盖当前查询',
    );
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
      FeedPage(
        items: [_post('a', 'x'), _post('b', 'x')],
        hasMore: true,
        nextCursor: 'c1',
      ),
      FeedPage(items: [_post('b', 'x'), _post('c', 'x')]),
    ]);
    final controller = FeedController(repository: feed);

    await controller.initialLoad();
    await controller.loadMore();

    expect(controller.state.items.map((post) => post.id), ['a', 'b', 'c']);
    expect(controller.state.hasMore, isFalse);
  });

  test('切换查询后旧分页请求不能追加到新列表', () async {
    final feed = _PendingFeed();
    final controller = FeedController(repository: feed);

    final initial = controller.setQuery(communityId: 'campus');
    feed.requests[0].completer.complete(
      FeedPage(
        items: [_post('campus-1', 'campus')],
        hasMore: true,
        nextCursor: 'campus-next',
      ),
    );
    await initial;

    final oldPage = controller.loadMore();
    final nextQuery = controller.setQuery(communityId: 'gaming');
    feed.requests[2].completer.complete(
      FeedPage(items: [_post('gaming-1', 'gaming')]),
    );
    await nextQuery;

    feed.requests[1].completer.complete(
      FeedPage(items: [_post('campus-2', 'campus')]),
    );
    await oldPage;

    expect(controller.state.items.map((post) => post.id), ['gaming-1']);
  });

  test('刷新期间旧的加载更多结果不能拼回刷新后的列表', () async {
    final feed = _PendingFeed();
    final controller = FeedController(repository: feed);

    final initial = controller.initialLoad();
    feed.requests[0].completer.complete(
      FeedPage(
        items: [_post('first', 'campus')],
        hasMore: true,
        nextCursor: 'page-2',
      ),
    );
    await initial;

    final oldLoadMore = controller.loadMore();
    expect(feed.requests[1].cursor, 'page-2');

    final refresh = controller.refresh();
    expect(feed.requests, hasLength(3));
    feed.requests[2].completer.complete(
      FeedPage(items: [_post('fresh', 'campus')]),
    );
    await refresh;

    feed.requests[1].completer.complete(
      FeedPage(items: [_post('stale', 'campus')]),
    );
    await oldLoadMore;

    expect(controller.state.items.map((post) => post.id), ['fresh']);
  });

  test('加载更多失败保留旧帖子，并允许使用原游标重试', () async {
    final feed = _FailingLoadMoreFeed();
    final controller = FeedController(repository: feed);

    await controller.initialLoad();
    await Future.wait([controller.loadMore(), controller.loadMore()]);

    expect(feed.cursors, [null, 'page-2'], reason: '并发触底只能请求一次');
    expect(controller.state.status, FeedStatus.success);
    expect(controller.state.items.map((post) => post.id), ['first']);
    expect(controller.state.error, isA<StateError>());
    expect(controller.state.nextCursor, 'page-2');

    await controller.loadMore();
    expect(feed.cursors, [null, 'page-2', 'page-2']);
  });
}
