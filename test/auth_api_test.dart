import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/auth_repository.dart';

void main() {
  test('ApiClient single-flights concurrent 401 refreshes', () async {
    final store = MemoryTokenStore(
      accessToken: 'expired-access',
      refreshToken: 'refresh-1',
    );
    var refreshCalls = 0;
    var feedCalls = 0;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: store,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return http.Response(
            jsonEncode({
              'access_token': 'fresh-access',
              'refresh_token': 'refresh-2',
              'token_type': 'Bearer',
              'expires_in': 900,
            }),
            200,
          );
        }
        feedCalls++;
        if (request.headers['Authorization'] == 'Bearer fresh-access') {
          return http.Response('{"items":[]}', 200);
        }
        return http.Response(
          '{"code":"INVALID_TOKEN","message":"expired"}',
          401,
        );
      }),
    );

    await Future.wait([
      client.getJson('/api/v1/feed/latest'),
      client.getJson('/api/v1/feed/latest'),
    ]);

    expect(refreshCalls, 1);
    expect(feedCalls, 4);
    expect(await store.readAccessToken(), 'fresh-access');
    expect(await store.readRefreshToken(), 'refresh-2');
    client.close();
  });

  test(
    'ApiClient preserves tokens after refresh network failure without retry loop',
    () async {
      final store = MemoryTokenStore(
        accessToken: 'expired-access',
        refreshToken: 'refresh-1',
      );
      var calls = 0;
      final client = ApiClient(
        baseUri: Uri.parse('https://example.com'),
        tokenStore: store,
        client: MockClient((request) async {
          calls++;
          if (request.url.path == '/api/v1/auth/refresh') {
            throw http.ClientException('offline');
          }
          return http.Response(
            '{"code":"INVALID_TOKEN","message":"expired"}',
            401,
          );
        }),
      );

      await expectLater(
        client.getJson('/api/v1/feed/latest'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 2);
      expect(await store.readAccessToken(), 'expired-access');
      expect(await store.readRefreshToken(), 'refresh-1');
      client.close();
    },
  );

  test('ApiClient clears tokens when refresh token is rejected', () async {
    final store = MemoryTokenStore(
      accessToken: 'expired-access',
      refreshToken: 'refresh-1',
    );
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: store,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          return http.Response(
            '{"code":"INVALID_TOKEN","message":"expired"}',
            401,
          );
        }
        return http.Response('{}', 401);
      }),
    );

    await expectLater(
      client.getJson('/api/v1/feed/latest'),
      throwsA(isA<ApiException>()),
    );
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    client.close();
  });

  test(
    'ApiClient notifies the app once when the session is invalidated',
    () async {
      final store = MemoryTokenStore(
        accessToken: 'expired-access',
        refreshToken: 'refresh-1',
      );
      var invalidationCalls = 0;
      final client = ApiClient(
        baseUri: Uri.parse('https://example.com'),
        tokenStore: store,
        onSessionInvalidated: () => invalidationCalls++,
        client: MockClient((request) async {
          return http.Response(
            '{"code":"INVALID_TOKEN","message":"expired"}',
            401,
          );
        }),
      );

      final first = client.getJson('/api/v1/feed/latest');
      final second = client.getJson('/api/v1/feed/latest');
      await expectLater(
        Future.wait<Map<String, dynamic>>([first, second]),
        throwsA(isA<ApiException>()),
      );

      expect(invalidationCalls, 1);
      client.close();
    },
  );

  test(
    'AuthRepository persists login tokens and clears them on logout',
    () async {
      final store = MemoryTokenStore();
      final client = ApiClient(
        baseUri: Uri.parse('https://example.com'),
        tokenStore: store,
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/login/password') {
            return http.Response(
              '{"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_in":900,"user":{"id":"u1","username":"user","nickname":"User","level":1,"status":"active","email":"user@test.com"}}',
              200,
            );
          }
          if (request.url.path == '/api/v1/auth/logout') {
            return http.Response('', 204);
          }
          throw StateError('unexpected request: ${request.url.path}');
        }),
      );
      final repository = AuthRepository(client: client, tokenStore: store);

      final session = await repository.loginWithPassword(
        email: 'user@test.com',
        password: 'password123',
      );
      expect(session.user.id, 'u1');
      expect(session.user.email, 'user@test.com');
      expect(await store.readAccessToken(), 'access-1');
      await repository.logout();
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      client.close();
    },
  );

  test('AuthRepository register and loginWithEmailCode flows', () async {
    final store = MemoryTokenStore();
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: store,
      client: MockClient((request) async {
        // print path
        if (request.url.path == '/api/v1/auth/code/request') {
          return http.Response(
            '{"expires_in":300,"retry_after":60,"delivery":"email","dev_code":"123456"}',
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/register') {
          return http.Response(
            '{"access_token":"reg-access","refresh_token":"reg-refresh","token_type":"Bearer","expires_in":900,"user":{"id":"u2","username":"usr_2","nickname":"新用户","level":1,"status":"active","email":"new@test.com"}}',
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path == '/api/v1/auth/login/code') {
          return http.Response(
            '{"access_token":"code-access","refresh_token":"code-refresh","token_type":"Bearer","expires_in":900,"user":{"id":"u3","username":"usr_3","nickname":"老用户","level":2,"status":"active","email":"old@test.com"}}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"code":"NOT_FOUND","message":"not found: ${request.url.path}"}', 404);
      }),
    );
    final repository = AuthRepository(client: client, tokenStore: store);

    final challenge = await repository.requestEmailCode(
      'new@test.com',
      scene: 'register',
    );
    expect(challenge.devCode, '123456');

    final regSession = await repository.register(
      email: 'new@test.com',
      code: '123456',
      password: 'password123',
      nickname: '新用户',
    );
    expect(regSession.user.email, 'new@test.com');
    expect(await store.readAccessToken(), 'reg-access');

    final codeSession = await repository.loginWithEmailCode(
      email: 'old@test.com',
      code: '123456',
    );
    expect(codeSession.user.email, 'old@test.com');
    expect(await store.readAccessToken(), 'code-access');
    client.close();
  });
}
