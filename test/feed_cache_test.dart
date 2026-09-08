import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luntan/data/cache/feed_cache.dart';
import 'package:luntan/domain/models.dart';

void main() {
  test('Feed 缓存保留推荐上下文置顶状态', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = FeedCacheService();
    final post = Post(
      id: 'pinned-post',
      authorId: 'author',
      communityId: 'community',
      title: '置顶推荐',
      content: '正文',
      createdAt: DateTime.utc(2026, 9, 8),
      updatedAt: DateTime.utc(2026, 9, 8),
      isRecommended: true,
      isRecommendationPinned: true,
    );

    await cache.write(
      accountScope: 'guest',
      communityId: 'community',
      sort: 'recommended',
      latestOrder: LatestOrder.comment,
      page: FeedPage(items: [post], hasMore: false),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isNotEmpty);
    final restored = await cache.read(
      accountScope: 'guest',
      communityId: 'community',
      sort: 'recommended',
      latestOrder: LatestOrder.comment,
    );

    expect(restored?.items.single.isRecommendationPinned, isTrue);
  });
}
