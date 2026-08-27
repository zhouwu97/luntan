import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/controllers/auth_controller.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/auth_repository.dart';
import 'package:luntan/screens/auth_screen.dart';
import 'package:luntan/theme/app_theme.dart';

const _userJson =
    '{"id":"u1","username":"testuser","nickname":"TestUser","level":1,"status":"active"}';
const _sessionJson =
    '{"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_in":900,"user":$_userJson}';

void main() {
  testWidgets('AuthScreen 初始为 Step 1，展示智能邮箱输入与常用后缀快捷标签', (tester) async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: MemoryTokenStore(),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final controller = AuthController(
      repository: AuthRepository(client: client, tokenStore: MemoryTokenStore()),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(
          controller: controller,
          onBrowse: () {},
        ),
      ),
    );

    expect(find.text('欢迎登录校园论坛'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.text('暂不登录，以游客身份体验'), findsOneWidget);

    // 输入前缀数字时应展示常用邮箱后缀 chips
    await tester.enterText(find.byType(TextField), '3170305904');
    await tester.pumpAndSettle();

    expect(find.text('@qq.com'), findsOneWidget);
    expect(find.text('@163.com'), findsOneWidget);
    expect(find.text('@gmail.com'), findsOneWidget);

    // 点击 @qq.com 自动补全
    await tester.tap(find.text('@qq.com'));
    await tester.pumpAndSettle();

    final emailField = tester.widget<TextField>(find.byType(TextField));
    expect(emailField.controller?.text, '3170305904@qq.com');
  });

  testWidgets('AuthScreen 点击获取验证码成功后平滑流转到 Step 2 (6位分格验证码与测试码)', (tester) async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: MemoryTokenStore(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/email/request') {
          return http.Response(
            '{"expires_in":300,"retry_after":60,"delivery":"email","dev_code":"123456"}',
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/email/verify') {
          return http.Response(_sessionJson, 200);
        }
        if (request.url.path == '/api/v1/me') {
          return http.Response(_userJson, 200);
        }
        return http.Response('{}', 404);
      }),
    );
    final controller = AuthController(
      repository: AuthRepository(client: client, tokenStore: MemoryTokenStore()),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(
          controller: controller,
          onBrowse: () {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'test@example.com');
    await tester.pump();

    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();

    // 应该切换到 Step 2
    expect(find.text('输入 6 位验证码'), findsOneWidget);
    expect(find.text('test@example.com'), findsOneWidget);
    expect(find.textContaining('开发环境验证码: 123456'), findsOneWidget);
    expect(find.textContaining('60s 后可重新获取'), findsOneWidget);

    // 点击修改返回 Step 1
    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();

    expect(find.text('欢迎登录校园论坛'), findsOneWidget);
  });

  testWidgets('AuthScreen 在 Step 2 点击开发环境测试码一键填入并成功登录', (tester) async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: MemoryTokenStore(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/email/request') {
          return http.Response(
            '{"expires_in":300,"retry_after":60,"delivery":"email","dev_code":"888999"}',
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/email/verify') {
          return http.Response(_sessionJson, 200);
        }
        if (request.url.path == '/api/v1/me') {
          return http.Response(_userJson, 200);
        }
        return http.Response('{}', 404);
      }),
    );
    final controller = AuthController(
      repository: AuthRepository(client: client, tokenStore: MemoryTokenStore()),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(
          controller: controller,
          onBrowse: () {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'user@test.com');
    await tester.pump();

    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();

    // 点击开发环境验证码
    await tester.tap(find.textContaining('开发环境验证码: 888999'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
    expect(controller.user?.id, 'u1');
  });

  testWidgets('AuthScreen 点击权限说明展示权限弹窗', (tester) async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: MemoryTokenStore(),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final controller = AuthController(
      repository: AuthRepository(client: client, tokenStore: MemoryTokenStore()),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(
          controller: controller,
          onBrowse: () {},
        ),
      ),
    );

    await tester.tap(find.text('权限说明'));
    await tester.pumpAndSettle();

    expect(find.text('账号权限说明'), findsOneWidget);
    expect(find.text('邮箱账号登录（完整体验）'), findsOneWidget);
    expect(find.text('游客模式体验'), findsOneWidget);
    expect(find.text('我知道了'), findsOneWidget);

    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();

    expect(find.text('账号权限说明'), findsNothing);
  });
}
