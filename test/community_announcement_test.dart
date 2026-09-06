import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/activity_management_screen.dart';

class _Repository extends PlatformRepository {
  _Repository() : super(ApiClient(baseUri: Uri.parse('https://example.com')));
  final calls = <String>[];
  Completer<void> pending = Completer<void>();
  @override
  Future<List<ActivityItem>> listAdminActivities({String? status}) async => [];
  @override
  Future<void> publishCommunityAnnouncement({
    required String id,
    required String title,
    required String content,
  }) {
    calls.add(id);
    return pending.future;
  }
}

void main() {
  testWidgets('公告发布防止重复点击，失败重试沿用同一编号', (tester) async {
    final repo = _Repository();
    final feedback = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityManagementScreen(
          repository: repo,
          onFeedback: feedback.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('发布社区公告'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '测试公告');
    await tester.enterText(find.byType(TextField).at(1), '测试正文');
    await tester.tap(find.widgetWithText(FilledButton, '发布公告'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '发布中…'))
          .onPressed,
      isNull,
    );
    repo.pending.completeError(StateError('网络失败'));
    await tester.pumpAndSettle();
    repo.pending = Completer<void>();
    await tester.tap(find.widgetWithText(FilledButton, '发布公告'));
    await tester.pump();
    expect(repo.calls, hasLength(2));
    expect(repo.calls[0], repo.calls[1]);
    repo.pending.complete();
    await tester.pumpAndSettle();
    expect(feedback, ['社区公告已发布']);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
