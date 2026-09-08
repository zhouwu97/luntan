import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/home_recommendations_screen.dart';

class _FakeRecommendationRepository extends PlatformRepository {
  _FakeRecommendationRepository(this.items)
    : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  final List<HomeRecommendation> items;
  List<String>? reorderedIds;
  String? removedId;
  bool? pinned;

  @override
  Future<List<HomeRecommendation>> listHomeRecommendations() async =>
      List<HomeRecommendation>.of(items);

  @override
  Future<void> reorderHomeRecommendations(List<String> postIds) async {
    reorderedIds = postIds;
  }

  @override
  Future<void> removeHomeRecommendation(String postId) async {
    removedId = postId;
  }

  @override
  Future<void> setHomeRecommendationPinned({
    required String postId,
    required bool pinned,
  }) async {
    this.pinned = pinned;
  }
}

HomeRecommendation _recommendation(String id, int position) =>
    HomeRecommendation(
      postId: id,
      position: position,
      recommendedBy: 'admin',
      recommendedAt: DateTime.utc(2026, 8, 26),
      title: '推荐帖子 $id',
      contentPreview: '正文',
      authorName: '管理员',
      communityName: '大型拆箱',
    );

void main() {
  testWidgets('首页推荐管理页支持置顶和取消置顶', (tester) async {
    final repository = _FakeRecommendationRepository([
      _recommendation('p1', 0),
    ]);
    var changedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeRecommendationsScreen(
          repository: repository,
          onFeedback: (_) {},
          onRecommendationChanged: () async => changedCount += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('在推荐中置顶'));
    await tester.pumpAndSettle();

    expect(repository.pinned, isTrue);
    expect(find.byTooltip('取消推荐置顶'), findsOneWidget);
    expect(changedCount, 1);
  });

  testWidgets('首页推荐页支持查看、移除和拖拽排序', (tester) async {
    final repository = _FakeRecommendationRepository([
      _recommendation('p1', 0),
      _recommendation('p2', 1),
    ]);
    final openedPostIds = <String>[];
    final feedback = <String>[];
    var changedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeRecommendationsScreen(
          key: UniqueKey(),
          repository: repository,
          onFeedback: feedback.add,
          onOpenPostId: openedPostIds.add,
          onRecommendationChanged: () async => changedCount += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1. 推荐帖子 p1'), findsOneWidget);
    expect(find.text('2. 推荐帖子 p2'), findsOneWidget);

    await tester.tap(find.text('1. 推荐帖子 p1'));
    expect(openedPostIds, ['p1']);

    await tester.tap(find.byTooltip('移出推荐').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移出推荐'));
    await tester.pumpAndSettle();
    expect(repository.removedId, 'p1');
    expect(find.text('1. 推荐帖子 p1'), findsNothing);
    expect(changedCount, 1);

    // 重新挂载两项，验证拖拽回调会提交新的顺序。
    repository.items
      ..clear()
      ..addAll([_recommendation('p1', 0), _recommendation('p2', 1)]);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeRecommendationsScreen(
          key: UniqueKey(),
          repository: repository,
          onFeedback: feedback.add,
          onRecommendationChanged: () async => changedCount += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    // ignore: unnecessary_non_null_assertion, deprecated_member_use
    reorderable.onReorder!(0, 2);
    await tester.pumpAndSettle();

    expect(repository.reorderedIds, ['p2', 'p1']);
    expect(changedCount, 2);
  });
}
