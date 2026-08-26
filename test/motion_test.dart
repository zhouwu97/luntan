import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/widgets/motion_tap_icon.dart';

void main() {
  testWidgets('高频图标在状态切换时完成形态切换', (tester) async {
    var active = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: IconButton(
              onPressed: () => setState(() => active = !active),
              icon: MotionTapIcon(
                active: active,
                activeIcon: Icons.favorite_rounded,
                inactiveIcon: Icons.favorite_border_rounded,
                activeColor: Colors.pink,
                inactiveColor: Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('减少动态效果时仍然立即展示最终状态', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: MotionTapIcon(
              active: true,
              activeIcon: Icons.bookmark_rounded,
              inactiveIcon: Icons.bookmark_border_rounded,
              activeColor: Colors.blue,
              inactiveColor: Colors.grey,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
