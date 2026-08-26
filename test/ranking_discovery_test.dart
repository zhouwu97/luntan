import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/controllers/interaction_controller.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart' hide RankingItem;
import 'package:luntan/data/api/ranking_repository.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/screens/ranking_page.dart';
import 'package:luntan/screens/search_screen.dart';
import 'package:luntan/widgets/search/search_post_row.dart';

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
          },
        ],
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
}

void main() {
  group('Ranking and Search Discovery API Tests', () {
    late RankingRepository rankingRepo;
    late PlatformRepository platformRepo;

    setUp(() {
      final fakeClient = _FakeApiClient();
      rankingRepo = RankingRepository(fakeClient);
      platformRepo = PlatformRepository(fakeClient);
    });

    test('RankingRepository.list parses category and segments', () async {
      final items = await rankingRepo.list();
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
  });
}
