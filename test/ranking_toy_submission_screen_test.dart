import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/publish_repository.dart';
import 'package:luntan/data/api/ranking_repository.dart';
import 'package:luntan/screens/ranking_toy_submission_screen.dart';

class _CapturingRankingRepository extends RankingRepository {
  _CapturingRankingRepository() : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  String? name;
  String? category;
  String? merchant;
  int? releaseYear;
  String? description;
  String? coverMediaId;
  int submitCalls = 0;

  @override
  Future<void> submitToy({
    required String name,
    required String category,
    String? merchant,
    int? releaseYear,
    String? description,
    String? coverMediaId,
  }) async {
    submitCalls++;
    this.name = name;
    this.category = category;
    this.merchant = merchant;
    this.releaseYear = releaseYear;
    this.description = description;
    this.coverMediaId = coverMediaId;
  }
}

class _NoopPublishRepository implements PublishRepository {
  @override
  Future<Map<String, dynamic>> createPost({
    required String communityId,
    required String type,
    required String title,
    required String content,
    required String idempotencyKey,
    List<String> mediaIds = const [],
    String? topic,
  }) =>
      throw UnimplementedError();

  @override
  Future<MediaUploadTicket> requestMediaUpload({
    required String fileName,
    required String mimeType,
    required int size,
    required String sha256,
    int width = 0,
    int height = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> uploadMedia({
    required MediaUploadTicket ticket,
    required List<int> bytes,
    required int size,
    required String sha256,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> completeMedia({
    required String mediaId,
    required int size,
    required String sha256,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteMedia(String mediaId) async {}
}

Future<void> _pumpScreen(WidgetTester tester, _CapturingRankingRepository repository) async {
  // 表单较长，默认 800x600 测试视口会触发 ListView 懒加载导致按钮未构建，放大视口让整表可见。
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        '/submission': (_) => RankingToySubmissionScreen(
          rankingRepository: repository,
          publishRepository: _NoopPublishRepository(),
        ),
      },
      home: const Scaffold(body: Center(child: Text('host-page'))),
    ),
  );
  // 以路由压栈方式打开，提交成功后的 pop 才有上一页可回，SnackBar 才有宿主 Scaffold。
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/submission');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('品类选项映射为服务端小写枚举值', (tester) async {
    expect(
      rankingToyCategoryOptions.map((option) => option.value).toList(),
      ['cup', 'small_hip', 'large_hip', 'half_body', 'lubricant'],
    );
    expect(rankingToyCategoryLabel('cup'), '飞机杯');
    expect(rankingToyCategoryLabel('small_hip'), '小型臀模');
    expect(rankingToyCategoryLabel('large_hip'), '大型臀模');
    expect(rankingToyCategoryLabel('half_body'), '半身腿模');
    expect(rankingToyCategoryLabel('lubricant'), '润滑油');
  });

  testWidgets('空名称或未选品类时不提交', (tester) async {
    final repository = _CapturingRankingRepository();
    await _pumpScreen(tester, repository);

    final submitButton = find.byKey(const ValueKey('submission-submit-button'));
    await tester.ensureVisible(submitButton);
    await tester.pump();
    await tester.tap(submitButton);
    await tester.pump();
    expect(repository.submitCalls, 0);
    expect(find.text('请填写玩具名称'), findsOneWidget);

    // SnackBar 的 4 秒自动隐藏计时器在入场动画完成后才启动，需推进两段假时钟让它彻底退场。
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('submission-name-field')), '测试玩具');
    await tester.tap(submitButton);
    await tester.pump();
    expect(repository.submitCalls, 0);
    expect(find.text('请选择品类'), findsOneWidget);
  });

  testWidgets('成功路径把表单参数提交到投稿接口', (tester) async {
    final repository = _CapturingRankingRepository();
    await _pumpScreen(tester, repository);

    final submitButton = find.byKey(const ValueKey('submission-submit-button'));
    await tester.enterText(find.byKey(const ValueKey('submission-name-field')), '新玩具甲');
    await tester.ensureVisible(find.byKey(const ValueKey('submission-category-chip-cup')));
    await tester.pump();
    await tester.tap(find.text('飞机杯'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('submission-merchant-field')), '品牌乙');
    await tester.enterText(find.byKey(const ValueKey('submission-year-field')), '2026');
    await tester.enterText(find.byKey(const ValueKey('submission-description-field')), '介绍文本');
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(repository.submitCalls, 1);
    expect(repository.name, '新玩具甲');
    expect(repository.category, 'cup');
    expect(repository.merchant, '品牌乙');
    expect(repository.releaseYear, 2026);
    expect(repository.description, '介绍文本');
    expect(repository.coverMediaId, isNull);
    expect(find.text('已提交，等待管理员审核'), findsOneWidget);
    expect(find.text('host-page'), findsOneWidget);
  });
}
