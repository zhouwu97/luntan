import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/repositories/mock_repositories.dart';

void main() {
  test('MockCommunityRepository 按接口返回动态 Community', () async {
    final repository = MockCommunityRepository();
    final communities = await repository.getCommunities();

    expect(communities, hasLength(3));
    expect(communities.map((item) => item.id), contains('community-campus'));
    expect(await repository.getCommunity('missing'), isNull);
  });

  test('MockFeedRepository 使用 FeedPage 和游标分页', () async {
    final repository = MockFeedRepository();
    final first = await repository.getLatestFeed(limit: 5);
    final second = await repository.getLatestFeed(
      cursor: first.nextCursor,
      limit: 5,
    );

    expect(first.items, hasLength(5));
    expect(first.hasMore, isTrue);
    expect(second.items, hasLength(5));
    final overlap = first.items
        .map((item) => item.id)
        .toSet()
        .intersection(second.items.map((item) => item.id).toSet());
    expect(overlap, isEmpty);
  });

  test('MockPostRepository 返回详情或空值', () async {
    final repository = MockPostRepository();
    final detail = await repository.getPost('u1');

    expect(detail?.post.id, 'u1');
    expect(await repository.getPost('missing'), isNull);
  });
}
