import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/platform_repository.dart';
import 'package:luntan/screens/moderation_console_screen.dart';

class _ModerationRepository extends PlatformRepository {
  _ModerationRepository()
    : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  final calls = <({String? cursor, String? source, String status})>[];
  final initial = Completer<ModerationCasePage>();
  final loadMoreA = Completer<ModerationCasePage>();
  final filtered = Completer<ModerationCasePage>();
  final loadMoreFiltered = Completer<ModerationCasePage>();

  @override
  Future<ModerationCasePage> listModerationCases({
    String status = '',
    String? source,
    String? cursor,
    int limit = 20,
  }) {
    calls.add((status: status, source: source, cursor: cursor));
    if (source == 'auto_rule' && cursor == null) return filtered.future;
    if (source == 'auto_rule' && cursor == 'cursor-b') {
      return loadMoreFiltered.future;
    }
    if (cursor == 'cursor-a') return loadMoreA.future;
    return initial.future;
  }

  @override
  Future<ModerationCaseDetail> getModerationCase(String caseId) {
    throw UnimplementedError();
  }
}

ModerationCasePage _page(String prefix, String nextCursor) {
  return ModerationCasePage(
    items: [
      for (var i = 0; i < 10; i++)
        ModerationCase(
          id: '$prefix-$i',
          targetType: 'post',
          targetId: 'post-$i',
          source: prefix == 'b' ? 'auto_rule' : 'user_report',
          riskLevel: 'low',
          status: 'open',
          communityId: 'community-1',
          createdAt: DateTime.utc(2026, 9, 1, 0, 0, i),
        ),
    ],
    nextCursor: nextCursor,
    hasMore: true,
  );
}

void main() {
  testWidgets('切换来源时会取消旧分页状态，并允许新来源继续加载下一页', (tester) async {
    final repository = _ModerationRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ModerationConsoleScreen(
          repository: repository,
          onFeedback: (_) {},
        ),
      ),
    );

    repository.initial.complete(_page('a', 'cursor-a'));
    await tester.pumpAndSettle();
    expect(repository.calls, hasLength(1));

    final list = find.byType(ListView).last;
    await tester.drag(list, const Offset(0, -1800));
    await tester.pump();
    expect(repository.calls.last.cursor, 'cursor-a');

    await tester.tap(find.text('自动规则'));
    await tester.pump();
    expect(repository.calls.last, (
      status: 'pending',
      source: 'auto_rule',
      cursor: null,
    ));

    repository.filtered.complete(_page('b', 'cursor-b'));
    await tester.pumpAndSettle();
    repository.loadMoreA.complete(_page('stale', 'stale-cursor'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).last, const Offset(0, -1800));
    await tester.pump();

    expect(repository.calls.last, (
      status: 'pending',
      source: 'auto_rule',
      cursor: 'cursor-b',
    ));
  });
}
