import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/mock_forum_data.dart';

void main() {
  test('板块和精华筛选使用独立状态', () {
    final store = ForumStore.seeded();
    expect(store.selectedSection, ForumSection.unboxing);
    expect(store.visiblePosts.every((post) => post.section == ForumSection.unboxing), isTrue);

    store.selectSection(ForumSection.community);
    store.selectSort(FeedSort.featured);
    expect(store.visiblePosts, isNotEmpty);
    expect(store.visiblePosts.every((post) => post.section == ForumSection.community && post.isFeatured), isTrue);
  });

  test('点赞、收藏和发布会更新本地状态', () {
    final store = ForumStore.seeded();
    final post = store.posts.first;
    final originalComments = post.comments;
    store.toggleLike(post);
    store.toggleBookmark(post);
    expect(post.comments, originalComments + 1);
    expect(post.isLiked, isTrue);
    expect(post.isBookmarked, isTrue);

    store.addPost(const PostDraft(title: '测试帖子', body: '测试正文', section: ForumSection.daily));
    expect(store.posts.first.title, '测试帖子');
    expect(store.selectedSection, ForumSection.daily);
    expect(store.selectedSort, FeedSort.latest);
  });

  test('刷新期间不会重复请求', () async {
    final store = ForumStore.seeded();
    final first = store.refresh();
    final second = store.refresh();
    expect(await second, 0);
    expect(await first, greaterThan(0));
    expect(store.isRefreshing, isFalse);
  });
}
