import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/controllers/feed_controller.dart';
import 'package:luntan/controllers/home_personal_feed_controller.dart';
import 'package:luntan/data/mock_forum_data.dart';

void main() {
  test('评论模式只保留收到其他用户评论的帖子并按最新评论排序', () async {
    final store = ForumStore.seeded();
    final now = DateTime.now();
    store.commentsByPost['u5'] = [
      Comment(
        id: 'self-comment',
        postId: 'u5',
        authorId: 'user-1',
        content: '这是我自己的评论',
        createdAt: now,
        updatedAt: now,
      ),
    ];
    final controller = HomePersonalFeedController(mockStore: store);

    await controller.selectMode(HomeFeedMode.receivedComments);

    expect(controller.state.status, FeedStatus.success);
    expect(controller.state.items.map((post) => post.id), ['u1']);
    expect(controller.activityAtFor('u1'), isNotNull);
    expect(controller.activityAtFor('u5'), isNull);
  });

  test('帖子模式严格按发布时间排序，不受评论数影响', () async {
    final controller = HomePersonalFeedController(
      mockStore: ForumStore.seeded(),
    );

    await controller.selectMode(HomeFeedMode.myPosts);

    expect(controller.state.items.map((post) => post.id), ['u1', 'u5']);
    expect(controller.state.items.first.commentCount, greaterThan(0));
    expect(
      controller.state.items.first.publishedAt!.isAfter(
        controller.state.items.last.publishedAt!,
      ),
      isTrue,
    );
  });

  test('切换模式时旧请求结果不能覆盖最后一次选择', () async {
    // Mock Feed 是同步数据源，但仍验证最后一次模式切换的状态边界；API
    // 分页/并发由同一代数保护逻辑处理。
    final controller = HomePersonalFeedController(
      mockStore: ForumStore.seeded(),
    );

    final first = controller.selectMode(HomeFeedMode.receivedComments);
    final second = controller.selectMode(HomeFeedMode.myPosts);
    await Future.wait([first, second]);

    expect(controller.state.mode, HomeFeedMode.myPosts);
    expect(controller.state.items.map((post) => post.id), ['u1', 'u5']);
  });
}
