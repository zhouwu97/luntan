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

  test('草稿快照往返保留社区分类与图片mediaId一一映射', () {
    final snapshot = ComposerDraftSnapshot(
      title: '标题',
      body: '正文',
      communityId: 'community-unboxing',
      topic: 'outfit',
      images: const [
        DraftImageData(localPath: '/a.jpg', mediaId: 'media-a'),
        DraftImageData(localPath: '/b.jpg', mediaId: null),
        DraftImageData(localPath: '/c.jpg', mediaId: 'media-c'),
      ],
      updatedAt: DateTime(2026, 8, 27),
    );

    final json = snapshot.toJson();
    final restored = ComposerDraftSnapshot.fromJson(json);

    expect(restored, isNotNull);
    expect(restored!.communityId, 'community-unboxing');
    expect(restored.title, '标题');
    expect(restored.topic, 'outfit');
    expect(restored.images.length, 3);
    expect(restored.images[0].localPath, '/a.jpg');
    expect(restored.images[0].mediaId, 'media-a');
    expect(restored.images[1].localPath, '/b.jpg');
    expect(restored.images[1].mediaId, isNull);
    expect(restored.images[2].localPath, '/c.jpg');
    expect(restored.images[2].mediaId, 'media-c');
  });

  test('草稿快照向前兼容解析旧版 local_image_paths 与 uploaded_media_ids', () {
    final legacyJson = {
      'title': '旧版标题',
      'body': '旧版正文',
      'local_image_paths': ['/p1.jpg', '/p2.jpg'],
      'uploaded_media_ids': ['m1'],
      'updated_at': DateTime(2026, 8, 27).toIso8601String(),
    };

    final restored = ComposerDraftSnapshot.fromJson(legacyJson);
    expect(restored, isNotNull);
    expect(restored!.images.length, 2);
    expect(restored.images[0].localPath, '/p1.jpg');
    expect(restored.images[0].mediaId, 'm1');
    expect(restored.images[1].localPath, '/p2.jpg');
    expect(restored.images[1].mediaId, isNull);
  });

  test('草稿存储键支持按 userId 隔离', () {
    expect(
      ComposerDraftStorage.storageKeyForUser('user-100'),
      'luntan.composer.draft.v2.user-100',
    );
    expect(
      ComposerDraftStorage.storageKeyForUser('user-200'),
      'luntan.composer.draft.v2.user-200',
    );
    expect(
      ComposerDraftStorage.storageKeyForUser('user@123!'),
      'luntan.composer.draft.v2.user_123_',
    );
    expect(
      ComposerDraftStorage.storageKeyForUser(null),
      'luntan.composer.draft.v2.global',
    );
  });
}

