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
    'AuthRepository persists login tokens and clears them on logout',
    () async {
      final store = MemoryTokenStore();
      final client = ApiClient(
        baseUri: Uri.parse('https://example.com'),
        tokenStore: store,
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/login') {
            return http.Response(
              '{"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_in":900,"user":{"id":"u1","username":"user","nickname":"User","level":1,"status":"active"}}',
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

      final session = await repository.login(
        username: 'user',
        password: 'password123',
      );
      expect(session.user.id, 'u1');
      expect(await store.readAccessToken(), 'access-1');
      await repository.logout();
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      client.close();
    },
  );
}
