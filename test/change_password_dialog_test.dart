import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/controllers/auth_controller.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/auth_repository.dart';
import 'package:luntan/screens/change_password_dialog.dart';

void main() {
  testWidgets('修改密码弹窗可切换邮箱验证码并请求 password_reset 场景', (tester) async {
    final store = MemoryTokenStore(accessToken: 'access-1');
    var codeRequestSent = false;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/email/request') {
        codeRequestSent = true;
        expect(request.body, contains('password_reset'));
        return http.Response(
          '{"expires_in":600,"retry_after":60,"delivery":"email"}',
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final apiClient = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: store,
      client: client,
    );
    final controller = AuthController(
      repository: AuthRepository(client: apiClient, tokenStore: store),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangePasswordDialog(
            controller: controller,
            email: 'user@example.com',
          ),
        ),
      ),
    );

    expect(find.text('修改密码'), findsOneWidget);
    await tester.tap(find.text('邮箱验证码'));
    await tester.pump();
    expect(find.textContaining('验证码将发送至 us***@example.com'), findsOneWidget);

    await tester.tap(find.text('获取验证码'));
    await tester.pump();
    expect(codeRequestSent, isTrue);
    expect(find.text('60s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
