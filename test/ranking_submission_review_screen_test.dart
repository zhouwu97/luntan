import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/ranking_submission_review_screen.dart';

class _FakePlatformRepository extends PlatformRepository {
  _FakePlatformRepository(this.items)
    : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  List<RankingToySubmission> items;
  String? reviewedId;
  bool? reviewedApprove;
  String? reviewedNote;
  Object? reviewError;
  int listCalls = 0;

  @override
  Future<List<RankingToySubmission>> listRankingSubmissions({
    String status = 'pending',
  }) async {
    listCalls++;
    return List<RankingToySubmission>.of(items);
  }

  @override
  Future<void> reviewRankingSubmission({
    required String id,
    required bool approve,
    String? note,
  }) async {
    if (reviewError != null) throw reviewError!;
    reviewedId = id;
    reviewedApprove = approve;
    reviewedNote = note;
  }
}

RankingToySubmission _submission(
  String id, {
  String status = 'pending',
  String note = '',
}) =>
    RankingToySubmission(
      id: id,
      name: '玩具甲$id',
      category: 'cup',
      merchant: '品牌乙',
      releaseYear: 2026,
      description: '好东西',
      status: status,
      reviewNote: note,
      createdAt: DateTime.utc(2026, 8, 29),
      submitterId: 'u-$id',
      submitterNickname: '投稿达人$id',
      intensity: 'advanced',
      tags: const ['慢玩', '软糯'],
    );

Widget _wrap(_FakePlatformRepository repository, {void Function(String)? onFeedback}) =>
    MaterialApp(
      home: RankingSubmissionReviewScreen(
        platformRepository: repository,
        onFeedback: onFeedback,
      ),
    );

void main() {
  testWidgets('渲染提交者昵称并通过投稿', (tester) async {
    final repository = _FakePlatformRepository([_submission('s1')]);
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('玩具甲s1'), findsOneWidget);
    expect(find.textContaining('投稿达人'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '通过'));
    await tester.pumpAndSettle();

    expect(repository.reviewedId, 's1');
    expect(repository.reviewedApprove, true);
  });

  testWidgets('驳回弹出原因输入并携带 note', (tester) async {
    final repository = _FakePlatformRepository([_submission('s2')]);
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '驳回'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '信息不完整');
    await tester.tap(find.widgetWithText(FilledButton, '驳回'));
    await tester.pumpAndSettle();

    expect(repository.reviewedId, 's2');
    expect(repository.reviewedApprove, false);
    expect(repository.reviewedNote, '信息不完整');
  });

  testWidgets('409 冲突提示后自动刷新', (tester) async {
    final repository = _FakePlatformRepository([_submission('s3')]);
    repository.reviewError = const ApiException(
      type: ApiErrorType.conflict,
      statusCode: 409,
      code: 'SUBMISSION_ALREADY_REVIEWED',
      message: '该提交已被处理',
    );
    final feedback = <String>[];
    await tester.pumpWidget(_wrap(repository, onFeedback: feedback.add));
    await tester.pumpAndSettle();
    final listCallsBefore = repository.listCalls;

    await tester.tap(find.widgetWithText(FilledButton, '通过'));
    await tester.pumpAndSettle();

    expect(feedback, contains('该提交已被处理'));
    expect(repository.listCalls, greaterThan(listCallsBefore));
  });
}
