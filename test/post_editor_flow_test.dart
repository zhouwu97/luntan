import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luntan/app.dart';
import 'package:luntan/data/composer_draft_storage.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/repository_provider.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/widgets/composer_sheet.dart';

void main() {
  testWidgets('底部 + 直接进入发布帖子页，不再出现发布方式选择', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LuntanApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('发布帖子'), findsOneWidget);
    expect(find.text('发布到论坛'), findsNothing);
    expect(find.text('发起投票'), findsNothing);
    expect(find.text('玩法分享'), findsNothing);
  });

  testWidgets('发帖页展示三个正式分类并默认选中传入分类，切换后发布携带正确社区', (tester) async {
    PostDraft? published;
    await tester.pumpWidget(
      MaterialApp(
        home: PostEditorScreen(
          initialCommunityId: 'community-unboxing',
          availableCommunities: ForumStore.seeded().communities,
          onPublish: (draft) async => published = draft,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 顶部三段选择器与首页一致，仅三个正式板块。
    expect(find.text('大型拆箱'), findsOneWidget);
    expect(find.text('酱紫社区'), findsOneWidget);
    expect(find.text('杂鱼日常'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '标题');
    await tester.enterText(find.byType(TextField).at(1), '正文');
    await tester.tap(find.text('杂鱼日常'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pumpAndSettle();

    expect(published, isNotNull);
    expect(published!.communityId, 'community-daily');
  });

  testWidgets('默认发布统一为 normal 类型并写入当前社区', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = ForumStore.seeded();
    await tester.pumpWidget(
      LuntanApp(repositories: ForumRepositories.mock(store: store)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '测试标题');
    await tester.enterText(find.byType(TextField).at(1), '测试正文');
    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pumpAndSettle();

    final post = store.posts.first;
    expect(post.type, PostType.normal);
    expect(post.communityId, 'community-campus');
    expect(post.title, '测试标题');
  });

  testWidgets('首页切换分类后发布写入对应社区', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = ForumStore.seeded();
    await tester.pumpWidget(
      LuntanApp(repositories: ForumRepositories.mock(store: store)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('杂鱼日常').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '日常标题');
    await tester.enterText(find.byType(TextField).at(1), '日常正文');
    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pumpAndSettle();

    final post = store.posts.first;
    expect(post.communityId, 'community-daily');
    expect(post.type, PostType.normal);
  });

  test('草稿快照往返保留社区分类', () {
    final snapshot = ComposerDraftSnapshot(
      title: '标题',
      body: '正文',
      communityId: 'community-unboxing',
      topic: 'outfit',
      localImagePaths: const ['/a.jpg'],
      uploadedMediaIds: const ['m1'],
      updatedAt: DateTime(2026, 8, 27),
    );

    final restored = ComposerDraftSnapshot.fromJson(snapshot.toJson());

    expect(restored, isNotNull);
    expect(restored!.communityId, 'community-unboxing');
    expect(restored.title, '标题');
    expect(restored.topic, 'outfit');
  });

  testWidgets('投票发布支持动态选项、多选并把配置交给发布回调', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    PostDraft? published;
    await tester.pumpWidget(
      MaterialApp(
        home: PostEditorScreen(
          initialCommunityId: 'community-campus',
          availableCommunities: ForumStore.seeded().communities,
          onPublish: (draft) async => published = draft,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('普通帖子'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('投票').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '投票标题');
    await tester.enterText(find.byType(TextField).at(1), '选项一');
    await tester.enterText(find.byType(TextField).at(2), '选项二');
    final addOption = find.text('添加选项');
    await tester.ensureVisible(addOption);
    await tester.tap(addOption);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(5));
    await tester.enterText(find.byType(TextField).at(3), '选项三');
    await tester.tap(find.text('允许多选'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField).at(4));
    await tester.enterText(find.byType(TextField).at(4), '正文');
    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pumpAndSettle();

    expect(published, isNotNull);
    expect(published!.isPoll, isTrue);
    expect(published!.pollOptions, ['选项一', '选项二', '选项三']);
    expect(published!.allowMultiple, isTrue);
  });
}
