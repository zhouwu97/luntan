import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';

void main() {
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
