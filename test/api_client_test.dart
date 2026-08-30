import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';

void main() {
  test('服务端认证错误码映射为可操作的中文提示', () {
    expect(
      userFacingApiMessage(
        const ApiException(
          type: ApiErrorType.unknown,
          code: 'INVALID_EMAIL_CODE',
          message: '验证码错误或已失效',
        ),
      ),
      '验证码错误，请检查后重试',
    );
    expect(
      userFacingApiMessage(
        const ApiException(
          type: ApiErrorType.serverError,
          code: 'MAIL_UNAVAILABLE',
          message: '邮件服务暂时不可用',
        ),
      ),
      '邮件服务暂时不可用，请稍后再试',
    );
    expect(
      userFacingApiMessage(
        const ApiException(
          type: ApiErrorType.forbidden,
          code: 'REGISTERED_ACCOUNT_REQUIRED',
          message: '游客不能发布',
        ),
      ),
      '游客可以评论和举报，登录邮箱账号后才能发布内容',
    );
  });

  test('ApiClient 解码 JSON 并保留查询参数', () async {
    Uri? requested;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        requested = request.url;
        return http.Response('{"items":[]}', 200);
      }),
    );

    final payload = await client.getJson(
      '/api/v1/feed/latest',
      queryParameters: {'limit': '20'},
    );
    expect(payload['items'], isEmpty);
    expect(requested?.queryParameters['limit'], '20');
  });

  test('ApiClient 统一映射 HTTP 错误', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode('{"code":"NOT_FOUND","message":"not-found"}'),
          404,
        ),
      ),
    );
    expect(
      () => client.getJson('/missing'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.type, 'type', ApiErrorType.notFound)
            .having((error) => error.code, 'code', 'NOT_FOUND')
            .having((error) => error.message, 'message', 'not-found'),
      ),
    );
  });

  test('ApiClient 保留服务端 request_id 和 details', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            '{"code":"INVALID_CURSOR","message":"cursor 无效","request_id":"req-1","details":{"field":"cursor"}}',
          ),
          400,
        ),
      ),
    );

    await expectLater(
      client.getJson('/feed'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'INVALID_CURSOR')
            .having((error) => error.requestId, 'requestId', 'req-1')
            .having((error) => error.details, 'details', {'field': 'cursor'}),
      ),
    );
  });

  test('ApiClient 映射网络错误和超时', () async {
    final networkClient = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(
      () => networkClient.getJson('/feed'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.type,
          'type',
          ApiErrorType.networkUnavailable,
        ),
      ),
    );

    final timeoutClient = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      timeout: const Duration(milliseconds: 1),
      client: MockClient(
        (_) async => Future<http.Response>.delayed(
          const Duration(milliseconds: 20),
          () => http.Response('{}', 200),
        ),
      ),
    );
    expect(
      () => timeoutClient.getJson('/feed'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.type,
          'type',
          ApiErrorType.timeout,
        ),
      ),
    );
  });

  test('Web cookie 刷新：无本地 refresh token 也能续期并保存新 access token', () async {
    final store = MemoryTokenStore(accessToken: 'expired-access');
    final refreshBodies = <Object?>[];
    var refreshCalls = 0;
    var meCalls = 0;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      tokenStore: store,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          refreshCalls++;
          refreshBodies.add(jsonDecode(request.body));
          // cookie 刷新成功的响应不返回 refresh_token
          return http.Response(
            '{"access_token":"new-access","token_type":"Bearer","expires_in":900}',
            200,
          );
        }
        if (request.url.path == '/api/v1/me') {
          meCalls++;
          if (meCalls == 1) {
            return http.Response('{"code":"TOKEN_EXPIRED","message":"expired"}', 401);
          }
          return http.Response('{"id":"usr_1"}', 200);
        }
        return http.Response('{}', 404);
      }),
    );

    final payload = await client.getJson('/api/v1/me');
    expect(payload['id'], 'usr_1');
    expect(meCalls, 2);
    expect(refreshCalls, 1);
    // body 中不携带 refresh_token，续期凭证由 HttpOnly cookie 承载
    expect(refreshBodies.single, <String, dynamic>{});
    expect(await store.readAccessToken(), 'new-access');
  });

  test('ApiClient 上传使用独立的长超时，不受普通请求超时影响', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      timeout: const Duration(milliseconds: 1),
      uploadTimeout: const Duration(milliseconds: 100),
      client: MockClient(
        (_) async => Future<http.Response>.delayed(
          const Duration(milliseconds: 20),
          () => http.Response('', 200),
        ),
      ),
    );

    await client.uploadBytes(Uri.parse('https://upload.example/media'), <int>[
      1,
      2,
      3,
    ], contentType: 'image/png');
  });
}
