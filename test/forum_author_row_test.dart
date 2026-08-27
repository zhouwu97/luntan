import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/domain/models.dart';
import 'package:luntan/widgets/forum_author_row.dart';

void main() {
  testWidgets('导入帖子的作者行使用服务端板块名称', (tester) async {
    final now = DateTime.now();
    final community = const Community(
      id: 'community-import-daily',
      slug: 'import-daily',
      name: '杂鱼日常',
      description: '源站导入',
      categoryId: 'category-import',
    );
    final post = Post(
      id: 'post-import-1',
      authorId: 'user-import-1',
      communityId: community.id,
      community: community,
      title: '真实帖子',
      content: '真实内容',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ForumAuthorRow(post: post)),
      ),
    );

    expect(find.textContaining('杂鱼日常 ·'), findsOneWidget);
    expect(find.textContaining('大型拆箱 ·'), findsNothing);
  });
}
