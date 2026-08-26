import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/widgets/search/search_community_row.dart';
import 'package:luntan/widgets/search/search_post_row.dart';
import 'package:luntan/widgets/search/search_user_row.dart';

void main() {
  testWidgets('SearchPostRow 正确渲染命中词高亮与度量数据', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPostRow(
            title: '新手小屯用黄油小姐二代吗？',
            snippet: '看榜单上面它排第一，有没有真实体验',
            authorName: '软萌研究员',
            authorLevel: 6,
            communityName: '大型拆箱',
            timeLabel: '5小时前',
            commentCount: 18,
            likeCount: 6,
            viewCount: 98,
            query: '黄油小姐',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('软萌研究员'), findsOneWidget);
    expect(find.text('Lv.6'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('98'), findsOneWidget);

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    expect(richTexts.isNotEmpty, isTrue);
  });

  testWidgets('SearchUserRow 正确渲染用户与等级', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchUserRow(
            nickname: '软萌研究员',
            username: 'ruanmeng',
            level: 6,
            signature: '慢玩与拆箱爱好者',
            query: '软萌',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Lv.6'), findsOneWidget);
    expect(find.textContaining('@ruanmeng'), findsOneWidget);
  });

  testWidgets('SearchCommunityRow 正确渲染板块与关注状态', (tester) async {
    bool followClicked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchCommunityRow(
            name: '大型拆箱',
            description: '玩具开箱与真实使用体验',
            isFollowing: false,
            onToggleFollow: () => followClicked = true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('大型拆箱', findRichText: true), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);

    await tester.tap(find.text('关注'));
    expect(followClicked, isTrue);
  });
}
