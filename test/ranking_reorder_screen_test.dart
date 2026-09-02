import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/ranking_reorder_screen.dart';

class _FakePlatformRepository extends PlatformRepository {
  _FakePlatformRepository(this.items)
    : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  List<RankingViewOrderItem> items;
  List<String>? orderedIds;
  String? savedTab;
  String? savedCategory;
  int? savedVersion;
  Object? reorderError;
  int loadCalls = 0;

  @override
  Future<RankingViewOrder> getRankingViewOrder({
    required String tab,
    required String category,
  }) async {
    loadCalls++;
    return RankingViewOrder(
      tab: tab,
      category: category,
      version: 7,
      items: List<RankingViewOrderItem>.of(items),
    );
  }

  @override
  Future<int> saveRankingViewOrder({
    required String tab,
    required String category,
    required List<String> orderedToyIds,
    required int version,
  }) async {
    if (reorderError != null) throw reorderError!;
    savedTab = tab;
    savedCategory = category;
    savedVersion = version;
    orderedIds = orderedToyIds;
    return version + 1;
  }
}

RankingViewOrderItem _toy(String id, int rank) =>
    RankingViewOrderItem(toyId: id, name: '玩具$id', sourceRank: rank);

Widget _wrap(
  _FakePlatformRepository platform, {
  String initialTab = '',
  String initialCategory = '',
  void Function(String)? onFeedback,
}) => MaterialApp(
  home: RankingReorderScreen(
    platformRepository: platform,
    initialTab: initialTab,
    initialCategory: initialCategory,
    onFeedback: onFeedback,
  ),
);

void main() {
  testWidgets('拖拽后仅提交当前榜单视图的新顺序', (tester) async {
    final platform = _FakePlatformRepository([
      _toy('t1', 1),
      _toy('t2', 2),
      _toy('t3', 3),
    ]);
    await tester.pumpWidget(
      _wrap(platform, initialTab: 'HIGH', initialCategory: 'LUBE'),
    );
    await tester.pumpAndSettle();

    expect(find.text('玩具t1'), findsOneWidget);

    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    // ignore: unnecessary_non_null_assertion, deprecated_member_use
    reorderable.onReorder!(0, 2);
    await tester.pumpAndSettle();

    expect(platform.orderedIds, ['t2', 't1', 't3']);
    expect(platform.savedTab, 'HIGH');
    expect(platform.savedCategory, 'LUBE');
    expect(platform.savedVersion, 7);
  });

  testWidgets('409 STALE 提示并重新拉取当前榜单视图', (tester) async {
    final platform = _FakePlatformRepository([
      _toy('t1', 1),
      _toy('t2', 2),
      _toy('t3', 3),
    ]);
    platform.reorderError = const ApiException(
      type: ApiErrorType.conflict,
      statusCode: 409,
      code: 'RANKING_VIEW_ORDER_STALE',
      message: '榜单有更新，请刷新后重试',
    );
    final feedback = <String>[];
    await tester.pumpWidget(_wrap(platform, onFeedback: feedback.add));
    await tester.pumpAndSettle();
    final loadCallsBefore = platform.loadCalls;

    final reorderable = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    // ignore: unnecessary_non_null_assertion, deprecated_member_use
    reorderable.onReorder!(0, 2);
    await tester.pumpAndSettle();

    expect(feedback, contains('当前榜单有更新，请刷新后重试'));
    expect(platform.loadCalls, greaterThan(loadCallsBefore));
    expect(find.text('玩具t1'), findsOneWidget);
  });
}
