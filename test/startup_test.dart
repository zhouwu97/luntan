import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/main.dart';

void main() {
  testWidgets('启动配置异常显示错误页而不是停留在原生启动页', (tester) async {
    final root = buildLuntanRootApp(
      loadRepositories: () =>
          throw StateError('production 环境必须配置 API_BASE_URL，禁止回退到 Mock'),
    );

    await tester.pumpWidget(root);

    expect(find.text('应用配置异常'), findsOneWidget);
    expect(find.text('请配置 API_BASE_URL 后重新构建应用'), findsOneWidget);
  });
}
