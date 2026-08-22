import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/domain/models.dart';

void main() {
  test('Post 使用关系 ID 和原始数值字段，不保存展示时间/浏览字符串', () {
    final now = DateTime.utc(2026, 1, 1);
    final author = User(id: 'u1', username: 'tester', nickname: '测试用户', createdAt: now, updatedAt: now);
    final community = Community(id: 'c1', slug: 'campus', name: '校园', description: '校园交流', categoryId: 'cat1');
    final post = Post(id: 'p1', authorId: author.id, communityId: community.id, author: author, community: community, title: '标题', content: '正文', viewCount: 3200, createdAt: now, updatedAt: now);

    expect(post.authorId, 'u1');
    expect(post.communityId, 'c1');
    expect(post.viewCount, 3200);
    expect(post.views, '3.2k');
    expect(relativeTimeLabel(now, now: now.add(const Duration(hours: 2))), '2小时前');
  });

  test('Category 和 Community 是两个独立领域对象', () {
    const category = CommunityCategory(id: 'cat1', name: '校园生活', slug: 'campus-life');
    const community = Community(id: 'c1', name: '校园问答', slug: 'campus-qa', description: '问答', categoryId: 'cat1');

    expect(category.id, isNot(community.id));
    expect(community.categoryId, category.id);
  });

  test('ViewerPostState 独立承载当前用户状态', () {
    final state = ViewerPostState(canEdit: true);
    expect(state.canEdit, isTrue);
    expect(state.hasLiked, isFalse);
    state.hasLiked = true;
    expect(state.hasLiked, isTrue);
  });
}
