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

  test('点赞只更新点赞状态，收藏和发布仍更新本地状态', () {
    final store = ForumStore.seeded();
    final post = store.posts.first;
    final originalComments = post.comments;
    final originalLikes = post.likeCount;
    store.toggleLike(post);
    store.toggleBookmark(post);
    expect(post.comments, originalComments);
    expect(post.likeCount, originalLikes + 1);
    expect(post.isLiked, isTrue);
    expect(post.isBookmarked, isTrue);

    store.toggleLike(post);
    expect(post.comments, originalComments);
    expect(post.likeCount, originalLikes);
    expect(post.isLiked, isFalse);

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
    expect(await first, 0);
    expect(store.isRefreshing, isFalse);
  });
}
