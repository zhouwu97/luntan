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
    '{"id":"u1","username":"usr_123456","nickname":"TestUser","level":1,"status":"active","email":"test@example.com","account_type":"email"}';
const _sessionJson =
    '{"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_in":900,"user":$_userJson}';

void main() {
  testWidgets('AuthScreen 初始为登录-验证码登录，展示智能邮箱输入与常用后缀快捷标签', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: MemoryTokenStore(),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final controller = AuthController(
      repository: AuthRepository(
        client: client,
        tokenStore: MemoryTokenStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(controller: controller, onBrowse: () {}),
      ),
    );

    expect(find.text('欢迎来到圣杯酱'), findsOneWidget);
    expect(find.text('登录'), findsWidgets);
    expect(find.text('注册'), findsWidgets);
    expect(find.text('验证码登录'), findsOneWidget);
    expect(find.text('密码登录'), findsOneWidget);
    expect(find.text('暂不登录，以游客身份体验'), findsOneWidget);

    // 切换到验证码登录
    await tester.tap(find.text('验证码登录'));
    await tester.pumpAndSettle();

    expect(find.text('获取验证码'), findsOneWidget);
    expect(find.text('登录并进入论坛'), findsOneWidget);

    // 输入前缀数字时应展示常用邮箱后缀 chips
    final emailField = find.byType(TextField).first;
    await tester.enterText(emailField, '3170305904');
    await tester.pumpAndSettle();

    expect(find.text('@qq.com'), findsOneWidget);
    expect(find.text('@163.com'), findsOneWidget);
    expect(find.text('@gmail.com'), findsOneWidget);

    // 点击 @qq.com 自动补全
    await tester.tap(find.text('@qq.com'));
    await tester.pumpAndSettle();

    final emailWidget = tester.widget<TextField>(emailField);
    expect(emailWidget.controller?.text, '3170305904@qq.com');
  });

  testWidgets('AuthScreen 切换登录/注册 Tab 保留已填写的邮箱', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: MemoryTokenStore(),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final controller = AuthController(
      repository: AuthRepository(
        client: client,
        tokenStore: MemoryTokenStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(controller: controller, onBrowse: () {}),
      ),
    );

    final emailField = find.byType(TextField).first;
    await tester.enterText(emailField, 'user@example.com');
    await tester.pumpAndSettle();

    // 点击注册 Tab
    await tester.tap(find.text('注册').first);
    await tester.pumpAndSettle();

    // 应该切换到注册表单，并保留邮箱
    expect(find.text('设置密码'), findsOneWidget);
    expect(find.text('确认密码'), findsOneWidget);
    expect(find.text('注册并进入论坛'), findsOneWidget);
    final registeredEmailWidget = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(registeredEmailWidget.controller?.text, 'user@example.com');

    // 切换回登录 Tab
    await tester.tap(find.text('登录').first);
    await tester.pumpAndSettle();
    expect(find.text('验证码登录'), findsOneWidget);
    expect(find.text('密码登录'), findsOneWidget);
    expect(find.text('登录'), findsWidgets);
    final backEmailWidget = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(backEmailWidget.controller?.text, 'user@example.com');
  });

  testWidgets('AuthScreen 密码登录流程与明暗文切换', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: MemoryTokenStore(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(_sessionJson, 200);
        }
        if (request.url.path == '/api/v1/me') {
          return http.Response(_userJson, 200);
        }
        return http.Response('{}', 404);
      }),
    );
    final controller = AuthController(
      repository: AuthRepository(
        client: client,
        tokenStore: MemoryTokenStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(controller: controller, onBrowse: () {}),
      ),
    );

    // 切换到密码登录
    await tester.tap(find.text('密码登录'));
    await tester.pumpAndSettle();

    expect(find.text('忘记密码？使用验证码登录'), findsOneWidget);

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'user@example.com');
    await tester.enterText(textFields.at(1), 'password123');
    await tester.pumpAndSettle();

    // 点击眼睛切换明暗文
    await tester.tap(find.byIcon(Icons.visibility_off_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);

    // 点击登录
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
    expect(controller.user?.email, 'test@example.com');
  });

  testWidgets('AuthScreen 验证码登录流程包含获取验证码、倒计时和开发验证码填入', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

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
      repository: AuthRepository(
        client: client,
        tokenStore: MemoryTokenStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(controller: controller, onBrowse: () {}),
      ),
    );

    // 切换到验证码登录
    await tester.tap(find.text('验证码登录'));
    await tester.pumpAndSettle();

    final emailField = find.byType(TextField).first;
    await tester.enterText(emailField, 'user@test.com');
    await tester.pump();

    // 点击获取验证码
    await tester.tap(find.text('获取验证码'));
    await tester.pumpAndSettle();

    expect(find.textContaining('开发环境验证码: 888999'), findsOneWidget);
    expect(find.textContaining('60s 后重发'), findsOneWidget);

    // 点击填入开发验证码
    await tester.tap(find.textContaining('开发环境验证码: 888999'));
    await tester.pumpAndSettle();

    // 点击登录并进入论坛
    await tester.ensureVisible(find.text('登录并进入论坛'));
    await tester.tap(find.text('登录并进入论坛'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
    expect(controller.user?.id, 'u1');
  });

  testWidgets('AuthScreen 注册流程与校验', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: MemoryTokenStore(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/email/request') {
          return http.Response(
            '{"expires_in":300,"retry_after":60,"delivery":"email","dev_code":"654321"}',
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/register') {
          return http.Response(_sessionJson, 201);
        }
        if (request.url.path == '/api/v1/me') {
          return http.Response(_userJson, 200);
        }
        return http.Response('{}', 404);
      }),
    );
    final controller = AuthController(
      repository: AuthRepository(
        client: client,
        tokenStore: MemoryTokenStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(controller: controller, onBrowse: () {}),
      ),
    );

    // 切换到注册
    await tester.tap(find.text('注册').first);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'newuser@example.com');
    await tester.enterText(fields.at(1), 'password123');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), '新杯友');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('注册并进入论坛'));
    await tester.tap(find.text('注册并进入论坛'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
  });

  testWidgets('AuthScreen 点击权限说明展示权限弹窗', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: MemoryTokenStore(),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final controller = AuthController(
      repository: AuthRepository(
        client: client,
        tokenStore: MemoryTokenStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(controller: controller, onBrowse: () {}),
      ),
    );

    await tester.tap(find.text('权限说明'));
    await tester.pumpAndSettle();

    expect(find.text('账号权限说明'), findsOneWidget);
    expect(find.text('正式邮箱账号（完整体验）'), findsOneWidget);
    expect(find.text('游客模式体验'), findsOneWidget);
    expect(find.text('我知道了'), findsOneWidget);

    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();

    expect(find.text('账号权限说明'), findsNothing);
  });
}
