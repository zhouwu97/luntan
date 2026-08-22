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
        (_) async => http.Response.bytes(utf8.encode('{"code":"NOT_FOUND","message":"不存在"}'), 404),
      ),
    );
    expect(
      () => client.getJson('/missing'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.type,
          'type',
          ApiErrorType.notFound,
        ),
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
}
