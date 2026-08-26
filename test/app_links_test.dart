import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/app_links.dart';

void main() {
  test('帖子和榜单链接使用同一公开域名', () {
    final post = Uri.parse(AppLinks.post('post-1'));
    final ranking = Uri.parse(AppLinks.ranking('toy-1'));

    expect(post.origin, ranking.origin);
    expect(post.path, '/posts/post-1');
    expect(ranking.path, '/ranking/toy-1');
  });
}
