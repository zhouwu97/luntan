import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/domain/models.dart';
import 'package:luntan/screens/home_screen.dart';

void main() {
  test('首页公开板块默认跳过 QA 测试板块并保留导入社区', () {
    final communities = [
      const Community(
        id: 'community_qa',
        slug: 'qa',
        name: 'QA测试板块',
        description: '测试数据',
        categoryId: 'cat-qa',
        sortOrder: 0,
      ),
      const Community(
        id: 'community-import-unboxing',
        slug: 'import-unboxing',
        name: '大型拆箱',
        description: '导入内容',
        categoryId: 'cat-import',
        sortOrder: 10,
      ),
      const Community(
        id: 'community-import-forum',
        slug: 'import-forum',
        name: '酱紫社区',
        description: '导入内容',
        categoryId: 'cat-import',
        sortOrder: 11,
      ),
    ];

    final visible = selectHomeCommunities(communities);

    expect(visible.map((item) => item.name), ['大型拆箱', '酱紫社区']);
    expect(visible, isNot(contains(communities.first)));
  });
}
