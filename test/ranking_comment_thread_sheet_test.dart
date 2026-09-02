import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/ranking_repository.dart';
import 'package:luntan/widgets/comments/ranking_comment_thread_sheet.dart';

class _MockRankingRepository extends RankingRepository {
  _MockRankingRepository({
    required this.replies,
    this.onDeleted,
  }) : super(ApiClient(baseUri: Uri.parse('https://example.com')));

  final List<RankingToyComment> replies;
  final ValueChanged<String>? onDeleted;

  @override
  Future<RankingToyCommentPage> listReplies({
    required String commentId,
    String? cursor,
    int limit = 20,
  }) async {
    return RankingToyCommentPage(
      items: List.of(replies),
      nextCursor: null,
      hasMore: false,
    );
  }

  @override
  Future<void> deleteComment(String commentId) async {
    onDeleted?.call(commentId);
  }
}

RankingToyComment _createComment({
  required String id,
  required String authorId,
  String content = '评论内容',
  String? parentId,
  int replyCount = 0,
}) {
  return RankingToyComment(
    id: id,
    authorId: authorId,
    username: 'user_$authorId',
    nickname: '昵称_$authorId',
    avatarUrl: '',
    level: 2,
    content: content,
    likeCount: 0,
    isLiked: false,
    createdAt: DateTime.now(),
    parentId: parentId,
    replyCount: replyCount,
    media: const [],
  );
}

void main() {
  testWidgets('普通用户在 RankingCommentThreadSheet 仅可复制，无删除选项', (tester) async {
    final root = _createComment(id: 'root-1', authorId: 'u1', replyCount: 1);
    final reply = _createComment(id: 'r-1', authorId: 'u2', parentId: 'root-1');
    final repo = _MockRankingRepository(replies: [reply]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RankingCommentThreadSheet(
            rootComment: root,
            repository: repo,
            canManageRanking: false,
            onReply: (target, content) async => reply,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 验证二级回复展示
    expect(find.text('昵称_u2'), findsOneWidget);

    // 点击回复项的更多操作
    final moreButtons = find.byTooltip('更多操作');
    expect(moreButtons, findsNWidgets(2)); // root 和 reply 各一个

    // 点击 reply 的更多按钮
    await tester.tap(moreButtons.last);
    await tester.pumpAndSettle();

    expect(find.text('复制内容'), findsOneWidget);
    expect(find.text('删除回复'), findsNothing);
    expect(find.text('删除评价'), findsNothing);
  });

  testWidgets('管理用户在 RankingCommentThreadSheet 可删除二级回复，且即时刷新回复数和列表', (
    tester,
  ) async {
    String? deletedCommentId;
    bool changedNotified = false;
    final root = _createComment(id: 'root-1', authorId: 'u1', replyCount: 1);
    final reply = _createComment(id: 'r-1', authorId: 'u2', parentId: 'root-1');
    final repo = _MockRankingRepository(
      replies: [reply],
      onDeleted: (id) => deletedCommentId = id,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RankingCommentThreadSheet(
            rootComment: root,
            repository: repo,
            canManageRanking: true,
            onReply: (target, content) async => reply,
            onChanged: () => changedNotified = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 初始展示 1 条回复
    expect(find.text('1 条回复'), findsOneWidget);
    expect(find.text('昵称_u2'), findsOneWidget);

    // 点击 reply 上的更多按钮
    final moreButtons = find.byTooltip('更多操作');
    await tester.tap(moreButtons.last);
    await tester.pumpAndSettle();

    // 弹出管理菜单，含有红色“删除回复”
    expect(find.text('删除回复'), findsOneWidget);

    // 点击删除回复 -> 弹出二次确认
    await tester.tap(find.text('删除回复'));
    await tester.pumpAndSettle();

    expect(find.text('确定要删除这条回复吗？此操作无法撤销。'), findsOneWidget);

    // 点击确认删除
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    // 断言后端删除被调用
    expect(deletedCommentId, 'r-1');
    expect(changedNotified, isTrue);

    // 列表已移除该回复，标题变为 0 条回复
    expect(find.text('昵称_u2'), findsNothing);
    expect(find.text('0 条回复'), findsOneWidget);
  });
}
