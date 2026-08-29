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

  testWidgets('点击头像或昵称回调作者 id，游客不触发', (tester) async {
    final now = DateTime.now();
    final community = const Community(
      id: 'community-tap',
      slug: 'tap',
      name: '点击社区',
      description: '测试社区',
      categoryId: 'category-tap',
    );
    final tappedIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumAuthorRow(
            post: Post(
              id: 'post-tap-1',
              authorId: 'user-tap-1',
              communityId: community.id,
              community: community,
              title: '点击测试',
              content: '内容',
              createdAt: now,
              updatedAt: now,
            ),
            onAuthorTap: tappedIds.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    expect(tappedIds, ['user-tap-1']);

    await tester.tap(find.text('匿名用户'));
    await tester.pump();
    expect(tappedIds, ['user-tap-1', 'user-tap-1']);
  });

  testWidgets('游客作者不触发主页跳转', (tester) async {
    final now = DateTime.now();
    final tappedIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForumAuthorRow(
            post: Post(
              id: 'post-tap-2',
              authorId: 'guest-abc',
              communityId: 'community-tap',
              title: '游客帖子',
              content: '内容',
              createdAt: now,
              updatedAt: now,
            ),
            onAuthorTap: tappedIds.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    expect(tappedIds, isEmpty);
  });
}
