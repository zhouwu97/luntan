import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/repositories.dart';
import 'package:luntan/screens/feature_page.dart';
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
    String? postType,
    bool? hasMedia,
  }) async {
    calls += 1;
    if (calls == 1) throw StateError('temporary failure');
    return const FeedPage(items: []);
  }
}

void main() {
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
}
