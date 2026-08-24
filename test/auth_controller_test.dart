import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/controllers/auth_controller.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/auth_repository.dart';

const _userJson =
    '{"id":"u1","username":"user","nickname":"User","level":1,"status":"active"}';
const _sessionJson =
    '{"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_in":900,"user":$_userJson}';

AuthController _controller({
  required http.Client client,
  required TokenStore store,
}) {
  final apiClient = ApiClient(
    baseUri: Uri.parse('https://example.com'),
    tokenStore: store,
    client: client,
  );
  return AuthController(
    repository: AuthRepository(client: apiClient, tokenStore: store),
  );
}

void main() {
  test('initialize 恢复有效会话进入已登录', () async {
    final store = MemoryTokenStore(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    final controller = _controller(
      store: store,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/me') {
          return http.Response(_userJson, 200);
        }
        return http.Response('{}', 404);
      }),
    );

    await controller.initialize();
    expect(controller.status, AuthStatus.authenticated);
    expect(controller.user?.id, 'u1');
  });

  test('invalidateSession 清理用户并回到未登录', () async {
    final store = MemoryTokenStore(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    final controller = _controller(
      store: store,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/me') {
          return http.Response(_userJson, 200);
        }
        return http.Response('{}', 404);
      }),
    );

    await controller.initialize();
    controller.invalidateSession();

    expect(controller.status, AuthStatus.unauthenticated);
    expect(controller.user, isNull);
  });

  test('initialize 遇 401（refresh 失效）回到未登录', () async {
    final store = MemoryTokenStore(
      accessToken: 'expired',
      refreshToken: 'invalid-refresh',
    );
    final controller = _controller(
      store: store,
      client: MockClient((request) async {
        return http.Response(
          '{"code":"INVALID_TOKEN","message":"expired"}',
          401,
        );
      }),
    );

    await controller.initialize();
    expect(controller.status, AuthStatus.unauthenticated);
    expect(controller.user, isNull);
  });

  test('initialize 断网但有本地会话时保留登录态（可重试，不误登出）', () async {
    final store = MemoryTokenStore(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    final controller = _controller(
      store: store,
      client: MockClient((request) async {
        throw http.ClientException('connection refused');
      }),
    );

    await controller.initialize();
    expect(controller.status, AuthStatus.error);
    expect(controller.user, isNull);
  });

  test('initialize 断网且无本地会话时按未登录处理', () async {
    final store = MemoryTokenStore();
    final controller = _controller(
      store: store,
      client: MockClient((request) async {
        throw http.ClientException('connection refused');
      }),
    );

    await controller.initialize();
    expect(controller.status, AuthStatus.unauthenticated);
  });

  test('login 成功进入已登录并保存会话', () async {
    final store = MemoryTokenStore();
    final controller = _controller(
      store: store,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(_sessionJson, 200);
        }
        return http.Response('{}', 404);
      }),
    );

    final ok = await controller.login(
      username: 'user',
      password: 'password123',
    );
    expect(ok, isTrue);
    expect(controller.status, AuthStatus.authenticated);
    expect(controller.user?.id, 'u1');
    expect(await store.readAccessToken(), 'access-1');
  });

  test('login 失败进入错误态且不保留用户', () async {
    final store = MemoryTokenStore();
    final controller = _controller(
      store: store,
      client: MockClient((request) async {
        return http.Response(
          '{"code":"INVALID_CREDENTIALS","message":"用户名或密码错误"}',
          401,
        );
      }),
    );

    final ok = await controller.login(username: 'user', password: 'wrong');
    expect(ok, isFalse);
    expect(controller.status, AuthStatus.error);
    expect(controller.user, isNull);
  });

  test('logout 清空用户和本地会话', () async {
    final store = MemoryTokenStore(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    var logoutCalled = false;
    final controller = _controller(
      store: store,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/logout') {
          logoutCalled = true;
          expect(jsonDecode(request.body), {'refresh_token': 'refresh-1'});
          return http.Response('', 204);
        }
        return http.Response('{}', 404);
      }),
    );

    await controller.logout();
    expect(logoutCalled, isTrue);
    expect(controller.status, AuthStatus.unauthenticated);
    expect(controller.user, isNull);
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });
}
