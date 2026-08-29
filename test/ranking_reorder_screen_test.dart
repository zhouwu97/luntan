import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/data/api/ranking_repository.dart';
import 'package:luntan/screens/ranking_reorder_screen.dart';

class _FakeRankingRepository extends RankingRepository {
  _FakeRankingRepository(this.toys)
    : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  List<RankingToy> toys;
  int listCalls = 0;

  @override
  Future<RankingList> list({String? tab, String? category}) async {
    listCalls++;
    return RankingList(items: List<RankingToy>.of(toys));
  }
}

class _FakePlatformRepository extends PlatformRepository {
  _FakePlatformRepository()
    : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  List<String>? reorderedIds;
  Object? reorderError;

  @override
  Future<void> reorderRankingToys(List<String> toyIds) async {
    if (reorderError != null) throw reorderError!;
    reorderedIds = toyIds;
  }
}

RankingToy _toy(String id, int rank) => RankingToy(
  id: id,
  rank: rank,
  name: '玩具$id',
  merchant: '品牌',
  releaseYear: 2026,
  description: '',
  tags: const [],
  assetKey: '',
  wantCount: 0,
  ratingCount: 0,
  score: 0,
  wanted: false,
  owned: false,
);

Widget _wrap(_FakeRankingRepository ranking, _FakePlatformRepository platform,
        {void Function(String)? onFeedback}) =>
    MaterialApp(
      home: RankingReorderScreen(
        rankingRepository: ranking,
        platformRepository: platform,
        onFeedback: onFeedback,
      ),
    );

void main() {
  testWidgets('拖拽后按新顺序提交 toy_ids', (tester) async {
    final ranking = _FakeRankingRepository([
      _toy('t1', 1),
      _toy('t2', 2),
      _toy('t3', 3),
    ]);
    final platform = _FakePlatformRepository();
    await tester.pumpWidget(_wrap(ranking, platform));
    await tester.pumpAndSettle();

    expect(find.text('玩具t1'), findsOneWidget);

    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    // ignore: unnecessary_non_null_assertion, deprecated_member_use
    reorderable.onReorder!(0, 2);
    await tester.pumpAndSettle();

    expect(platform.reorderedIds, ['t2', 't1', 't3']);
    expect(find.text('综合热榜名次已保存'), findsNothing);
  });

  testWidgets('409 STALE 提示并重新拉取榜单', (tester) async {
    final ranking = _FakeRankingRepository([
      _toy('t1', 1),
      _toy('t2', 2),
      _toy('t3', 3),
    ]);
    final platform = _FakePlatformRepository();
    platform.reorderError = const ApiException(
      type: ApiErrorType.conflict,
      statusCode: 409,
      code: 'RANKING_REORDER_STALE',
      message: '榜单有更新，请刷新后重试',
    );
    final feedback = <String>[];
    await tester.pumpWidget(_wrap(ranking, platform, onFeedback: feedback.add));
    await tester.pumpAndSettle();
    final listCallsBefore = ranking.listCalls;

    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    // ignore: unnecessary_non_null_assertion, deprecated_member_use
    reorderable.onReorder!(0, 2);
    await tester.pumpAndSettle();

    expect(feedback, contains('榜单有更新，请刷新后重试'));
    expect(ranking.listCalls, greaterThan(listCallsBefore));
    // 重拉后顺序恢复
    expect(find.text('玩具t1'), findsOneWidget);
  });
}
