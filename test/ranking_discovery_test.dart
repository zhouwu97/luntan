import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/controllers/interaction_controller.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart' hide RankingItem;
import 'package:luntan/data/api/ranking_repository.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/ranking_cache.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/screens/ranking_page.dart';
import 'package:luntan/screens/search_screen.dart';
import 'package:luntan/widgets/search/search_post_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUri: Uri.parse('http://127.0.0.1:8080'));

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/api/v1/ranking/toys') {
      return {
        'items': [
          {
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
            'viewer_state': {'wanted': true, 'owned': false, 'rating': 9},
          },
          {
            'id': 'toy-shendai',
            'rank': 2,
            'name': '神代雪乃',
            'merchant': 'TMT',
            'release_year': 2026,
            'description': '一字开腿',
            'tags': ['顶级材料', '一字开腿'],
            'asset_key': 'thumb_05.jpg',
            'want_count': 148,
            'rating_count': 11,
            'score': 9.8,
            'category': 'half_body',
            'segments': ['beginner', 'advanced'],
            'viewer_state': {'wanted': false, 'owned': true, 'rating': null},
          },
        ],
      };
    }

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
        'viewer_state': {'wanted': true, 'owned': false, 'rating': 9},
        'rating_distribution': {'10': 10, '9': 5, '8': 2},
        'comments': [
          {
            'id': 'c-1',
            'author': {
              'id': 'u-1',
              'username': 'tester',
              'nickname': '测试酱',
              'level': 4,
              'author_rating': 9,
            },
            'content': '手感极佳，软糯适中',
            'like_count': 12,
            'created_at': '2026-08-22T10:00:00Z',
            'viewer_state': {'has_liked': true},
            'root_id': 'c-1',
            'reply_count': 1,
          },
        ],
      };
    }

    if (path == '/api/v1/ranking/toy-comments/c-1/replies') {
      return {
        'items': [
          {
            'id': 'reply-1',
            'author': {
              'id': 'u-2',
              'username': 'reply-user',
              'nickname': '回复用户',
              'level': 2,
            },
            'content': '这是楼中楼里的回复',
            'root_id': 'c-1',
            'parent_id': 'reply-0',
            'reply_to_user_id': 'u-1',
            'like_count': 2,
            'created_at': '2026-08-22T10:01:00Z',
            'viewer_state': {'has_liked': false},
          },
        ],
        'has_more': false,
      };
    }

    if (path == '/api/v1/search') {
      return {
        'toys': [
          {
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
          },
        ],
        'posts': [
          {
            'id': 'p-1',
            'title': '关于黄油小姐二代的使用体验',
            'content_preview': '开箱体验分享...',
            'community_id': 'c-1',
            'community_name': '慢玩交流',
            'created_at': '2026-08-22T10:00:00Z',
          },
        ],
        'users': [],
        'communities': [],
        'has_more': false,
      };
    }

    return {};
  }

  final List<String> deletedPaths = [];

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    deletedPaths.add(path);
    return {};
  }
}

class _FailingRankingRepository extends RankingRepository {
  _FailingRankingRepository() : super(_FakeApiClient());

  @override
  Future<RankingToyDetail> detail(
    String toyId, {
    String commentSort = 'weight',
  }) async {
    throw StateError('network down');
  }
}

class _FailingListRankingRepository extends RankingRepository {
  _FailingListRankingRepository() : super(_FakeApiClient());

  @override
  Future<RankingList> list({String? tab, String? category}) =>
      Future.error(StateError('network down'));
}

class _SortFailureApiClient extends _FakeApiClient {
  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) {
    if (path == '/api/v1/ranking/toys/toy-butter-2' &&
        queryParameters?['comment_sort'] == 'latest') {
      throw StateError('sort unavailable');
    }
    return super.getJson(
      path,
      headers: headers,
      queryParameters: queryParameters,
    );
  }
}

class _FakeApiClientWithPreviews extends _FakeApiClient {
  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    final res = await super.getJson(
      path,
      headers: headers,
      queryParameters: queryParameters,
    );
    if (path == '/api/v1/ranking/toys/toy-butter-2') {
      final copy = Map<String, dynamic>.from(res);
      copy['comments'] = [
        {
          'id': 'c-1',
          'author': {
            'id': 'u-1',
            'username': 'tester',
            'nickname': '测试酱',
            'level': 4,
            'author_rating': 9,
          },
          'content': '手感极佳，软糯适中',
          'like_count': 12,
          'created_at': '2026-08-22T10:00:00Z',
          'viewer_state': {'has_liked': true},
          'root_id': 'c-1',
          'reply_count': 5,
          'reply_preview': [
            {
              'id': 'r-1',
              'author': {
                'id': 'u-2',
                'username': 'user2',
                'nickname': '热心车手',
                'level': 2,
              },
              'content': '二级热评一',
              'like_count': 20,
              'created_at': '2026-08-22T10:05:00Z',
              'viewer_state': {'has_liked': false},
              'root_id': 'c-1',
              'parent_id': 'c-1',
              'reply_count': 0,
            },
            {
              'id': 'r-2',
              'author': {
                'id': 'u-3',
                'username': 'user3',
                'nickname': '资深玩家',
                'level': 3,
              },
              'content': '二级热评二',
              'like_count': 15,
              'created_at': '2026-08-22T10:10:00Z',
              'viewer_state': {'has_liked': false},
              'root_id': 'c-1',
              'parent_id': 'c-1',
              'reply_count': 0,
            },
          ],
        },
      ];
      return copy;
    }
    return res;
  }
}

void main() {
  testWidgets('排行榜列表失败时不展示静态演示数据', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RankingPage(
          repository: _FailingListRankingRepository(),
          cache: MemoryRankingCache(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('排行榜暂时无法加载'), findsOneWidget);
    expect(find.text('黄油小姐 二代'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
  });

  group('Ranking and Search Discovery API Tests', () {
    late RankingRepository rankingRepo;
    late PlatformRepository platformRepo;

    setUp(() {
      final fakeClient = _FakeApiClient();
      rankingRepo = RankingRepository(fakeClient);
      platformRepo = PlatformRepository(fakeClient);
    });

    test('RankingRepository.list parses category and segments', () async {
      final items = (await rankingRepo.list()).items;
      expect(items.length, 2);
      expect(items[0].id, 'toy-butter-2');
      expect(items[0].category, 'cup');
      expect(items[0].segments, ['beginner']);
      expect(items[1].category, 'half_body');
      expect(items[1].segments, ['beginner', 'advanced']);
    });

    test(
      'RankingRepository.detail parses ratingDistribution and authorRating',
      () async {
        final detail = await rankingRepo.detail('toy-butter-2');
        expect(detail.toy.category, 'cup');
        expect(detail.ratingDistribution[10], 10);
        expect(detail.ratingDistribution[9], 5);
        expect(detail.comments.length, 1);
        expect(detail.comments[0].authorRating, 9);
        expect(detail.comments[0].level, 4);
      },
    );

    test('PlatformRepository.search parses toys in SearchResult', () async {
      final res = await platformRepo.search('黄油', type: 'all');
      expect(res.toys.length, 1);
      expect(res.toys[0].name, '黄油小姐 二代');
      expect(res.toys[0].category, 'cup');
      expect(res.posts.length, 1);
      expect(res.isEmpty, false);
    });
  });

  group('RankingPage UI & Search Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('RankingPage performs local search and filters list', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RankingPage(repository: RankingRepository(_FakeApiClient())),
        ),
      );
      await tester.pumpAndSettle();

      // Verify search input is present
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('黄油小姐 二代'), findsWidgets);

      // Search for specific product
      await tester.enterText(find.byType(TextField), '神代');
      await tester.pumpAndSettle();

      // Top banner NO.1 is hidden during search and results are displayed
      expect(find.text('找到 1 个榜单结果'), findsOneWidget);
      expect(find.text('神代雪乃'), findsOneWidget);
      expect(find.text('黄油小姐 二代'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();
      expect(find.text('黄油小姐 二代'), findsWidgets);
    });

    testWidgets(
      'RankingItemDetailPage shows rating distribution and author comment info',
      (tester) async {
        final rankingRepo = RankingRepository(_FakeApiClient());
        const item = RankingItem(
          id: 'toy-butter-2',
          rank: 1,
          name: '黄油小姐 二代',
          hot: '401人想冲',
          tags: ['奶香', '软糯'],
          ratings: '17人评分',
          score: '8.7',
          asset: 'assets/ranking/hero.webp',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: RankingItemDetailPage(item: item, repository: rankingRepo),
          ),
        );
        await tester.pumpAndSettle();

        // Verify rating distribution card is rendered
        expect(find.text('酱友评分'), findsOneWidget);
        expect(find.text('8.7'), findsOneWidget);
        // Verify level 4 is rendered on the comment
        expect(find.text('LV4'), findsOneWidget);
        expect(find.text('9分'), findsOneWidget);
        expect(find.text('手感极佳，软糯适中'), findsOneWidget);
      },
    );

    testWidgets('榜单评价点击回复后打开独立楼中楼并平铺嵌套回复', (tester) async {
      final rankingRepo = RankingRepository(_FakeApiClient());
      const item = RankingItem(
        id: 'toy-butter-2',
        rank: 1,
        name: '黄油小姐 二代',
        hot: '401人想冲',
        tags: ['奶香'],
        ratings: '17人评分',
        score: '8.7',
        asset: 'assets/ranking/hero.webp',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RankingItemDetailPage(
            item: item,
            repository: rankingRepo,
            isAuthenticated: true,
            canComment: true,
            canLike: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final repliesLink = find.text('查看 1 条回复 ›');
      await tester.ensureVisible(repliesLink);
      await tester.tap(repliesLink);
      await tester.pumpAndSettle();

      expect(find.text('1 条回复'), findsOneWidget);
      expect(find.text('这是楼中楼里的回复'), findsOneWidget);
      expect(find.text('回复 @测试酱'), findsOneWidget);
    });

    testWidgets('榜单评价有 reply_preview 时正常外显高赞二级回复和折叠按钮', (tester) async {
      final client = _FakeApiClientWithPreviews();
      final rankingRepo = RankingRepository(client);
      const item = RankingItem(
        id: 'toy-butter-2',
        rank: 1,
        name: '黄油小姐 二代',
        hot: '401人想冲',
        tags: ['奶香'],
        ratings: '17人评分',
        score: '8.7',
        asset: 'assets/ranking/hero.webp',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RankingItemDetailPage(
            item: item,
            repository: rankingRepo,
            isAuthenticated: true,
            canComment: true,
            canLike: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证外显了前4条二级回复中的高赞回复
      expect(find.textContaining('二级热评一', findRichText: true), findsOneWidget);
      expect(find.textContaining('二级热评二', findRichText: true), findsOneWidget);
      expect(find.text('查看全部 5 条回复 ›'), findsOneWidget);
    });

    testWidgets('榜单评价 API 失败时不展示 Mock 评价', (tester) async {
      const item = RankingItem(
        id: 'toy-butter-2',
        rank: 1,
        name: '黄油小姐 二代',
        hot: '401人想冲',
        tags: ['奶香'],
        ratings: '17人评分',
        score: '8.7',
        asset: 'assets/ranking/hero.webp',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RankingItemDetailPage(
            item: item,
            repository: _FailingRankingRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('菜菜M'), findsNothing);
      expect(find.text('评价加载失败，请重试'), findsWidgets);
    });

    testWidgets('榜单排序请求失败时保留原排序标签', (tester) async {
      const item = RankingItem(
        id: 'toy-butter-2',
        rank: 1,
        name: '黄油小姐 二代',
        hot: '401人想冲',
        tags: ['奶香'],
        ratings: '17人评分',
        score: '8.7',
        asset: 'assets/ranking/hero.webp',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RankingItemDetailPage(
            item: item,
            repository: RankingRepository(_SortFailureApiClient()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('按权重排序'), findsOneWidget);
      await tester.tap(find.text('按权重排序'));
      await tester.pumpAndSettle();
      expect(find.text('按权重排序'), findsOneWidget);
      expect(find.text('按时间排序'), findsNothing);
    });
  });

  group('SearchScreen Toy Integration Tests', () {
    testWidgets('SearchScreen displays toy results and switches tabs', (
      tester,
    ) async {
      final fakeClient = _FakeApiClient();
      final platform = PlatformRepository(fakeClient);
      final store = ForumStore.seeded();
      final interaction = InteractionController(
        repository: MockInteractionRepository(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            store: store,
            platform: platform,
            rankingRepository: RankingRepository(fakeClient),
            onOpenPost: (_) {},
            onOpenPostId: (_) {},
            interactionController: interaction,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter query
      await tester.enterText(find.byType(TextField), '黄油');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify both toy and post results are rendered
      expect(find.text('榜单商品'), findsOneWidget);
      expect(find.text('黄油小姐 二代'), findsOneWidget);
      expect(find.byType(SearchPostRow), findsOneWidget);

      // Switch to Toy tab
      await tester.tap(find.text('榜单'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('黄油小姐 二代'), findsOneWidget);
    });

    testWidgets('RankingItemDetailPage 管理员点击一级评价展示删除评价并可删除', (tester) async {
      final fakeClient = _FakeApiClient();
      final rankingRepo = RankingRepository(fakeClient);
      const item = RankingItem(
        id: 'toy-butter-2',
        rank: 1,
        name: '黄油小姐 二代',
        hot: '401人想冲',
        tags: ['奶香'],
        ratings: '17人评分',
        score: '8.7',
        asset: 'assets/ranking/hero.webp',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RankingItemDetailPage(
            item: item,
            repository: rankingRepo,
            isAuthenticated: true,
            canManageRanking: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('手感极佳，软糯适中'), findsOneWidget);

      final moreBtn = find.byTooltip('更多操作');
      await tester.ensureVisible(moreBtn);
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      expect(find.text('复制内容'), findsOneWidget);
      expect(find.text('删除评价'), findsOneWidget);

      await tester.tap(find.text('删除评价'));
      await tester.pumpAndSettle();

      expect(find.text('确定要删除这条评价吗？此操作无法撤销。'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(fakeClient.deletedPaths, contains('/api/v1/ranking/toy-comments/c-1'));
    });

    testWidgets('RankingItemDetailPage 普通用户点击一级评价仅展示复制内容', (tester) async {
      final fakeClient = _FakeApiClient();
      final rankingRepo = RankingRepository(fakeClient);
      const item = RankingItem(
        id: 'toy-butter-2',
        rank: 1,
        name: '黄油小姐 二代',
        hot: '401人想冲',
        tags: ['奶香'],
        ratings: '17人评分',
        score: '8.7',
        asset: 'assets/ranking/hero.webp',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RankingItemDetailPage(
            item: item,
            repository: rankingRepo,
            isAuthenticated: true,
            canManageRanking: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('手感极佳，软糯适中'), findsOneWidget);

      final moreBtn = find.byTooltip('更多操作');
      await tester.ensureVisible(moreBtn);
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      expect(find.text('复制内容'), findsOneWidget);
      expect(find.text('删除评价'), findsNothing);
    });
  });
}
