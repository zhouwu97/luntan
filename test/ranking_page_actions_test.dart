import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/data/api/publish_repository.dart';
import 'package:luntan/data/api/ranking_repository.dart';
import 'package:luntan/screens/ranking_page.dart';

class _StubRankingRepository extends RankingRepository {
  _StubRankingRepository()
    : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  @override
  Future<RankingList> list({String? tab, String? category}) async {
    return const RankingList(items: []);
  }
}

class _StubPublishRepository implements PublishRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubPlatformRepository extends PlatformRepository {
  _StubPlatformRepository()
    : super(ApiClient(baseUri: Uri.parse('https://example.com')));
}

void main() {
  testWidgets('有投稿能力时榜单页展示投稿与调序入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RankingPage(
          repository: _StubRankingRepository(),
          platformRepository: _StubPlatformRepository(),
          publishRepository: _StubPublishRepository(),
          canManageRanking: true,
        ),
      ),
    );
    // 榜单页存在持续动画，不能使用 pumpAndSettle，改为有限帧推进。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('投稿新玩具'), findsOneWidget);
    expect(find.byTooltip('调整榜单名次'), findsOneWidget);
  });

  testWidgets('无投稿能力时隐藏投稿与调序入口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RankingPage()),
    );
    // 本地数据模式存在持续动画，不能使用 pumpAndSettle，改为有限帧推进。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('投稿新玩具'), findsNothing);
    expect(find.byTooltip('调整榜单名次'), findsNothing);
  });
}
