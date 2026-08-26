import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/domain/repositories.dart';
import 'package:luntan/screens/feature_page.dart';
import 'package:luntan/screens/ranking_page.dart';
import 'package:luntan/controllers/interaction_controller.dart';

class _RetryFeatureFeed implements FeedRepository, QueryableFeedRepository {
  int calls = 0;

  @override
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20}) =>
      getFeed(cursor: cursor, limit: limit);

  @override
  Future<FeedPage> getFeed({
    String? cursor,
    int limit = 20,
    String? communityId,
    String sort = 'recommended',
    LatestOrder latestOrder = LatestOrder.comment,
    String? postType,
    bool? hasMedia,
  }) async {
    calls += 1;
    if (calls == 1) throw StateError('temporary failure');
    return const FeedPage(items: []);
  }
}

void main() {
  testWidgets('玩具排行榜复刻网站结构与排行内容', (tester) async {
    final interactionController = InteractionController(
      repository: MockInteractionRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturePage(
          type: FeatureType.ranking,
          store: ForumStore.seeded(),
          onOpenPost: (_) {},
          interactionController: interactionController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('综合热榜'), findsOneWidget);
    expect(find.text('慢玩入门'), findsOneWidget);
    expect(find.text('飞机杯'), findsOneWidget);
    expect(find.text('NO.1 本周霸权'), findsOneWidget);
    expect(find.text('黄油小姐 二代'), findsOneWidget);
    expect(find.text('樱川爱 二代'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == '第1名 黄油小姐 二代，8.7 分',
      ),
      findsOneWidget,
    );
  });

  testWidgets('榜单卡片可以打开详情并返回', (tester) async {
    final interactionController = InteractionController(
      repository: MockInteractionRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturePage(
          type: FeatureType.ranking,
          store: ForumStore.seeded(),
          onOpenPost: (_) {},
          interactionController: interactionController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('返回'), findsOneWidget);
    final cardTitle = find.text('樱川爱 二代').first;
    await tester.tap(cardTitle);
    await tester.pumpAndSettle();

    expect(find.byType(RankingItemDetailPage), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('综合热榜'), findsOneWidget);
  });

  testWidgets('功能页加载失败后重试会重新发起请求', (tester) async {
    final repository = _RetryFeatureFeed();
    final interactionController = InteractionController(
      repository: MockInteractionRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturePage(
          type: FeatureType.gameShare,
          store: ForumStore.seeded(),
          onOpenPost: (_) {},
          interactionController: interactionController,
          feedRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    await tester.tap(find.text('返回重试'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(find.text('这里还没有内容'), findsOneWidget);
  });

  testWidgets('排行榜标签可以交互', (tester) async {
    final interactionController = InteractionController(
      repository: MockInteractionRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturePage(
          type: FeatureType.ranking,
          store: ForumStore.seeded(),
          onOpenPost: (_) {},
          interactionController: interactionController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('榨汁玩具'));
    await tester.pumpAndSettle();
    expect(find.text('NO.1 本周霸权'), findsNothing);
    expect(find.text('可可狼姬'), findsOneWidget);
  });
}
