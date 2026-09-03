import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/ranking_repository.dart';
import 'package:luntan/screens/ranking_page.dart';

class _OwnedRatingFakeApiClient extends ApiClient {
  _OwnedRatingFakeApiClient() : super(baseUri: Uri.parse('http://127.0.0.1:8080'));

  bool ownedState = false;
  int? userRating;
  int rateCalls = 0;
  int setOwnedCalls = 0;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/api/v1/ranking/toys/toy-butter-2') {
      return {
        'id': 'toy-butter-2',
        'rank': 1,
        'name': '黄油小姐 二代',
        'merchant': 'COC',
        'release_year': 2025,
        'description': '奶香软糯',
        'tags': ['奶香', '软糯'],
        'asset_key': 'hero.webp',
        'want_count': 401,
        'rating_count': 17,
        'score': 8.7,
        'category': 'cup',
        'segments': ['beginner'],
        'viewer_state': {
          'wanted': false,
          'owned': ownedState,
          'rating': userRating,
        },
        'rating_distribution': {'10': 10, '9': 5, '8': 2},
        'comments': [],
      };
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? requestTimeout,
  }) async {
    if (path == '/api/v1/ranking/toys/toy-butter-2/owned') {
      setOwnedCalls++;
      ownedState = true;
      return {};
    }
    return {};
  }

  bool failDelete = false;

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? requestTimeout,
  }) async {
    if (path == '/api/v1/ranking/toys/toy-butter-2/owned') {
      setOwnedCalls++;
      if (failDelete) {
        throw const ApiException(
          type: ApiErrorType.unknown,
          statusCode: 500,
          code: 'server_error',
          message: '服务器开小差了',
        );
      }
      ownedState = false;
      return {};
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? requestTimeout,
  }) async {
    if (path == '/api/v1/ranking/toys/toy-butter-2/rating') {
      rateCalls++;
      final map = body as Map<String, dynamic>?;
      userRating = map?['score'] as int? ?? 10;
      return {
        'id': 'toy-butter-2',
        'rank': 1,
        'name': '黄油小姐 二代',
        'merchant': 'COC',
        'release_year': 2025,
        'description': '奶香软糯',
        'tags': ['奶香', '软糯'],
        'asset_key': 'hero.webp',
        'want_count': 401,
        'rating_count': 18,
        'score': 8.8,
        'category': 'cup',
        'segments': ['beginner'],
        'viewer_state': {
          'wanted': false,
          'owned': ownedState,
          'rating': userRating,
        },
      };
    }
    return {};
  }
}

void main() {
  const testItem = RankingItem(
    id: 'toy-butter-2',
    rank: 1,
    name: '黄油小姐 二代',
    hot: '401人想冲',
    tags: ['奶香', '软糯'],
    ratings: '17人评分',
    score: '8.7',
    asset: 'assets/ranking/hero.webp',
  );

  testWidgets('点击买过自动弹出打分弹窗并可提交评分与买过标记', (tester) async {
    final client = _OwnedRatingFakeApiClient();
    final repo = RankingRepository(client);

    await tester.pumpWidget(
      MaterialApp(
        home: RankingItemDetailPage(
          item: testItem,
          repository: repo,
          isAuthenticated: true,
          canVote: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 初始状态为“买过”
    expect(find.text('买过'), findsOneWidget);

    // 点击“买过”
    await tester.tap(find.text('买过'));
    await tester.pumpAndSettle();

    // 弹出打分弹窗
    expect(find.text('给这款玩具评分'), findsOneWidget);
    expect(find.text('提交评分'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // 提交评分
    await tester.tap(find.text('提交评分'));
    await tester.pumpAndSettle();

    expect(client.setOwnedCalls, greaterThanOrEqualTo(1));
    expect(client.rateCalls, 1);
    expect(find.text('已标记买过，评分已保存'), findsOneWidget);
    expect(find.text('已买过'), findsOneWidget);
  });

  testWidgets('点击买过后若取消打分弹窗，仍保留已买过状态', (tester) async {
    final client = _OwnedRatingFakeApiClient();
    final repo = RankingRepository(client);

    await tester.pumpWidget(
      MaterialApp(
        home: RankingItemDetailPage(
          item: testItem,
          repository: repo,
          isAuthenticated: true,
          canVote: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 点击“买过”
    await tester.tap(find.text('买过'));
    await tester.pumpAndSettle();

    expect(find.text('给这款玩具评分'), findsOneWidget);

    // 点击“取消”
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(client.setOwnedCalls, 1);
    expect(find.text('已标记为买过'), findsOneWidget);
    expect(find.text('已买过'), findsOneWidget);
  });

  testWidgets('已买过时点击已买过可修改评分或取消买过标记', (tester) async {
    final client = _OwnedRatingFakeApiClient();
    client.ownedState = true;
    client.userRating = 8;
    final repo = RankingRepository(client);

    await tester.pumpWidget(
      MaterialApp(
        home: RankingItemDetailPage(
          item: testItem,
          repository: repo,
          isAuthenticated: true,
          canVote: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 初始状态为“已买过”
    expect(find.text('已买过'), findsOneWidget);

    // 点击“已买过”
    await tester.tap(find.text('已买过'));
    await tester.pumpAndSettle();

    // 弹出修改评分弹窗
    expect(find.text('修改评分'), findsOneWidget);
    expect(find.text('取消买过'), findsOneWidget);

    // 点击“取消买过”
    await tester.tap(find.text('取消买过'));
    await tester.pumpAndSettle();

    expect(find.text('已取消“买过”标记'), findsOneWidget);
    expect(find.text('买过'), findsOneWidget);
  });

  testWidgets('取消买过如果服务器报错，不提示已取消买过标记且恢复已买过状态', (tester) async {
    final client = _OwnedRatingFakeApiClient();
    client.ownedState = true;
    client.userRating = 8;
    client.failDelete = true;
    final repo = RankingRepository(client);

    await tester.pumpWidget(
      MaterialApp(
        home: RankingItemDetailPage(
          item: testItem,
          repository: repo,
          isAuthenticated: true,
          canVote: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已买过'), findsOneWidget);

    // 点击“已买过”弹出打分弹窗
    await tester.tap(find.text('已买过'));
    await tester.pumpAndSettle();

    // 点击“取消买过”触发失败
    await tester.tap(find.text('取消买过'));
    await tester.pumpAndSettle();

    // 应该只出现服务器错误提示，绝不出现“已取消“买过”标记”
    expect(find.text('服务器开小差了'), findsOneWidget);
    expect(find.text('已取消“买过”标记'), findsNothing);
    // 状态依旧保持为“已买过”
    expect(find.text('已买过'), findsOneWidget);
  });
}
