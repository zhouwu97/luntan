import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/controllers/interaction_controller.dart';
import 'package:luntan/data/mock_forum_data.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/screens/search_screen.dart';

void main() {
  late ForumStore store;
  late InteractionController interactionController;

  setUp(() {
    store = ForumStore.seeded();
    interactionController = InteractionController(
      repository: MockInteractionRepository(),
    );
  });

  Widget buildTestScreen({
    ValueChanged<Post>? onOpenPost,
    ValueChanged<String>? onOpenPostId,
    ValueChanged<String>? onOpenCommunityId,
  }) {
    return MaterialApp(
      home: SearchScreen(
        store: store,
        interactionController: interactionController,
        onOpenPost: onOpenPost ?? (_) {},
        onOpenPostId: onOpenPostId ?? (_) {},
        onOpenCommunityId: onOpenCommunityId,
      ),
    );
  }

  testWidgets('搜索空状态展示最近搜索、猜你想搜与推荐板块', (tester) async {
    await tester.pumpWidget(buildTestScreen());
    await tester.pumpAndSettle();

    expect(find.text('猜你想搜'), findsOneWidget);
    expect(find.text('推荐板块'), findsOneWidget);
    expect(find.text('黄油小姐'), findsWidgets);
    expect(find.text('大型拆箱', findRichText: true), findsWidgets);
  });

  testWidgets('点击猜你想搜 Tag 自动触发搜索并展示对应结果', (tester) async {
    await tester.pumpWidget(buildTestScreen());
    await tester.pumpAndSettle();

    // 点击猜你想搜中的“黄油小姐”
    await tester.tap(find.text('黄油小姐').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('黄油小姐'), findsWidgets);
    expect(find.text('帖子'), findsWidgets);
  });

  testWidgets('切换分类 Tab 过滤结果', (tester) async {
    await tester.pumpWidget(buildTestScreen());
    await tester.pumpAndSettle();

    // 输入搜索词
    await tester.enterText(find.byType(TextField), '二代');
    await tester.pumpAndSettle();

    expect(find.text('综合'), findsOneWidget);
    expect(find.text('帖子'), findsWidgets);

    // 切换到用户 Tab
    await tester.tap(find.text('用户'));
    await tester.pumpAndSettle();

    // 切换到板块 Tab
    await tester.tap(find.text('板块'));
    await tester.pumpAndSettle();
  });
}
