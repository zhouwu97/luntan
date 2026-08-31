import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/domain/repositories.dart';
import 'package:luntan/screens/feature_page.dart';
import 'package:luntan/screens/ranking_page.dart';
import 'package:luntan/controllers/interaction_controller.dart';

class _FakePlatformRepository extends PlatformRepository {
  _FakePlatformRepository(this._activities)
      : super(ApiClient(baseUri: Uri.parse('http://localhost')));

  final List<ActivityItem> _activities;

  @override
  Future<List<ActivityItem>> listPublicActivities() async => _activities;
}

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
    String? topic,
  }) async {
    calls += 1;
    if (calls == 1) throw StateError('temporary failure');
    return const FeedPage(items: []);
  }
}

class _ActivityFeatureFeed implements FeedRepository, QueryableFeedRepository {
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
    String? topic,
  }) async {
    return FeedPage(items: [
      Post(
        id: 'legacy-activity-post',
        authorId: 'admin',
        communityId: 'community-campus',
        title: '旧活动帖子',
        content: '旧活动正文',
        type: PostType.activity,
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      ),
    ]);
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

  testWidgets('热门帖子展示极简元信息且不再包含大横幅', (tester) async {
    final interactionController = InteractionController(
      repository: MockInteractionRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturePage(
          type: FeatureType.hot,
          store: ForumStore.seeded(),
          onOpenPost: (_) {},
          interactionController: interactionController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('按热度排序'), findsOneWidget);
    expect(find.text('最多展示 20 条'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
    expect(find.textContaining('社区里正在被大家讨论的内容'), findsNothing);
  });

  testWidgets('活动页无活动时展示极简空状态', (tester) async {
    final interactionController = InteractionController(
      repository: MockInteractionRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturePage(
          type: FeatureType.activity,
          store: ForumStore.uiOnly(),
          onOpenPost: (_) {},
          interactionController: interactionController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无活动'), findsOneWidget);
    expect(find.text('管理员发布活动后，会直接显示在这里。'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
  });

  testWidgets('活动页有活动时展示紧凑活动列表', (tester) async {
    final interactionController = InteractionController(
      repository: MockInteractionRepository(),
    );
    final activityItem = ActivityItem(
      id: 'act-1',
      title: '秋季社区线下交流',
      description: '带上你最近在玩的东西，现场交流使用和保养经验。',
      location: '社区活动室',
      status: 'active',
      startAt: DateTime(2026, 9, 5, 14, 0),
      createdBy: 'admin',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    final platformRepo = _FakePlatformRepository([activityItem]);

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturePage(
          type: FeatureType.activity,
          store: ForumStore.uiOnly(),
          onOpenPost: (_) {},
          interactionController: interactionController,
          platformRepository: platformRepo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('近期活动'), findsOneWidget);
    expect(find.text('秋季社区线下交流'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('05'), findsOneWidget);
    expect(find.text('9 月'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('社区活动室'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
  });

  testWidgets('活动页以活动实体为唯一数据源，不被旧活动帖子遮蔽', (tester) async {
    final interactionController = InteractionController(
      repository: MockInteractionRepository(),
    );
    final activityItem = ActivityItem(
      id: 'act-ssot',
      title: '活动实体标题',
      description: '活动实体描述',
      status: 'upcoming',
      startAt: DateTime(2026, 9, 5, 14, 0),
      createdBy: 'admin',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FeaturePage(
          type: FeatureType.activity,
          store: ForumStore.uiOnly(),
          onOpenPost: (_) {},
          interactionController: interactionController,
          feedRepository: _ActivityFeatureFeed(),
          platformRepository: _FakePlatformRepository([activityItem]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('活动实体标题'), findsOneWidget);
    expect(find.text('旧活动帖子'), findsNothing);
  });
}
