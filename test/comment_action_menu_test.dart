import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/data/api/ranking_repository.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/widgets/comments/comment_action_menu.dart';

Comment _mockComment({
  required String id,
  required String authorId,
  String content = '这是一条普通评论',
}) {
  final now = DateTime.now();
  return Comment(
    id: id,
    postId: 'post-1',
    authorId: authorId,
    author: User(
      id: authorId,
      username: 'author_$authorId',
      nickname: '用户$authorId',
      level: 1,
      createdAt: now,
      updatedAt: now,
    ),
    content: content,
    createdAt: now,
    updatedAt: now,
  );
}

RankingToyComment _mockRankingComment({
  required String id,
  required String authorId,
  String content = '这是一条榜单评价',
  String? parentId,
}) {
  return RankingToyComment(
    id: id,
    authorId: authorId,
    username: 'author_$authorId',
    nickname: '评价者$authorId',
    avatarUrl: '',
    level: 2,
    content: content,
    likeCount: 5,
    isLiked: false,
    createdAt: DateTime.now(),
    parentId: parentId,
    replyCount: 0,
    media: const [],
  );
}

void main() {
  group('showCommentActionMenu 安全区避让与权限控制', () {
    testWidgets('普通用户即便为评论作者，也不显示“删除评论”按钮', (tester) async {
      final comment = _mockComment(id: 'c1', authorId: 'u1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCommentActionMenu(
                  context,
                  comment: comment,
                  currentUserId: 'u1',
                  canModerate: false,
                  onCopy: () {},
                  onEdit: () {},
                  onDelete: () {},
                ),
                child: const Text('打开菜单'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开菜单'));
      await tester.pumpAndSettle();

      expect(find.text('复制内容'), findsOneWidget);
      expect(find.text('编辑评论'), findsOneWidget);
      expect(find.text('删除评论'), findsNothing);
    });

    testWidgets('管理用户展示红色“删除评论”，点击后需二次确认才执行 onDelete', (tester) async {
      bool deleted = false;
      final comment = _mockComment(id: 'c1', authorId: 'u2');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCommentActionMenu(
                  context,
                  comment: comment,
                  currentUserId: 'u1',
                  canModerate: true,
                  onCopy: () {},
                  onDelete: () => deleted = true,
                ),
                child: const Text('打开菜单'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开菜单'));
      await tester.pumpAndSettle();

      // 菜单中应有红色删除评论项
      final deleteTileFinder = find.text('删除评论');
      expect(deleteTileFinder, findsOneWidget);

      // 点击删除项 -> 弹出二次确认对话框
      await tester.tap(deleteTileFinder);
      await tester.pumpAndSettle();

      expect(find.text('确定要删除这条评论吗？此操作无法撤销。'), findsOneWidget);
      expect(deleted, isFalse);

      // 点击取消 -> 不触发删除
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(deleted, isFalse);

      // 再次打开并点击确认删除
      await tester.tap(find.text('打开菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除评论'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });

    testWidgets('菜单容器包含 bottomInset + 10 避让内边距', (tester) async {
      final comment = _mockComment(id: 'c1', authorId: 'u1');

      tester.view.viewPadding = const FakeViewPadding(bottom: 48.0);
      addTearDown(tester.view.resetViewPadding);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCommentActionMenu(
                  context,
                  comment: comment,
                  currentUserId: 'u1',
                  canModerate: true,
                  onCopy: () {},
                  onDelete: () {},
                ),
                child: const Text('打开菜单'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开菜单'));
      await tester.pumpAndSettle();

      // 验证底部外边距为系统 viewPadding.bottom + 10
      final expectedBottom =
          MediaQueryData.fromView(tester.view).viewPadding.bottom + 10;
      expect(expectedBottom, greaterThan(10));
      final paddings = tester.widgetList<Padding>(find.byType(Padding));
      final hasSafePadding = paddings.any(
        (p) => p.padding == EdgeInsets.only(bottom: expectedBottom),
      );
      expect(hasSafePadding, isTrue);
    });
  });

  group('showRankingCommentActionMenu 榜单评价操作菜单', () {
    testWidgets('普通用户（canManageRanking=false）仅显示复制内容', (tester) async {
      final rankingComment = _mockRankingComment(id: 'rc1', authorId: 'u1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showRankingCommentActionMenu(
                  context,
                  comment: rankingComment,
                  canManageRanking: false,
                  onCopy: () {},
                  onDelete: () {},
                ),
                child: const Text('打开榜单菜单'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开榜单菜单'));
      await tester.pumpAndSettle();

      expect(find.text('复制内容'), findsOneWidget);
      expect(find.text('删除评价'), findsNothing);
      expect(find.text('删除回复'), findsNothing);
    });

    testWidgets('管理用户（canManageRanking=true）对一级评价显示“删除评价”并支持二次确认', (
      tester,
    ) async {
      bool deleted = false;
      final rankingComment = _mockRankingComment(id: 'rc1', authorId: 'u1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showRankingCommentActionMenu(
                  context,
                  comment: rankingComment,
                  canManageRanking: true,
                  isReply: false,
                  onCopy: () {},
                  onDelete: () => deleted = true,
                ),
                child: const Text('打开榜单菜单'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开榜单菜单'));
      await tester.pumpAndSettle();

      expect(find.text('复制内容'), findsOneWidget);
      expect(find.text('删除评价'), findsOneWidget);

      await tester.tap(find.text('删除评价'));
      await tester.pumpAndSettle();

      expect(find.text('确定要删除这条评价吗？此操作无法撤销。'), findsOneWidget);
      expect(deleted, isFalse);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });

    testWidgets('管理用户对二级回复显示“删除回复”', (tester) async {
      bool deleted = false;
      final rankingReply = _mockRankingComment(
        id: 'reply1',
        authorId: 'u2',
        parentId: 'rc1',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showRankingCommentActionMenu(
                  context,
                  comment: rankingReply,
                  canManageRanking: true,
                  isReply: true,
                  onCopy: () {},
                  onDelete: () => deleted = true,
                ),
                child: const Text('打开回复菜单'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开回复菜单'));
      await tester.pumpAndSettle();

      expect(find.text('复制内容'), findsOneWidget);
      expect(find.text('删除回复'), findsOneWidget);

      await tester.tap(find.text('删除回复'));
      await tester.pumpAndSettle();

      expect(find.text('确定要删除这条回复吗？此操作无法撤销。'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });
  });
}
