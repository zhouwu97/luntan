import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/publish_repository.dart';

void main() {
  test('原子投票发布把投票数据放入同一条发帖请求', () async {
    late http.Request request;
    final repository = ApiPublishRepository(
      ApiClient(
        baseUri: Uri.parse('https://api.example'),
        client: MockClient((value) async {
          request = value;
          return http.Response('{"id":"post-1","type":"poll"}', 201);
        }),
      ),
    );

    await repository.createPollPost(
      communityId: 'community-1',
      title: '投票标题',
      content: '正文',
      idempotencyKey: 'poll-key-1',
      options: const ['A', 'B'],
    );

    expect(request.method, 'POST');
    expect(request.url.path, '/api/v1/posts');
    expect(request.headers['idempotency-key'], 'poll-key-1');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['type'], 'poll');
    expect((body['poll'] as Map<String, dynamic>)['options'], ['A', 'B']);
  });

  test('媒体直传使用申请凭证时声明的真实 MIME 类型', () async {
    String? uploadedContentType;
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/media/upload-token') {
          return http.Response(
            jsonEncode({
              'media_id': 'media-1',
              'upload_url': 'https://upload.example/object',
              'upload_method': 'PUT',
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            }),
            201,
          );
        }
        if (request.url.host == 'upload.example') {
          uploadedContentType = request.headers['content-type'];
          return http.Response('', 200);
        }
        if (request.url.path == '/api/v1/media/media-1/complete') {
          return http.Response('{"status":"ready"}', 200);
        }
        return http.Response('not found', 404);
      }),
    );
    final repository = ApiPublishRepository(client);

    final ticket = await repository.requestMediaUpload(
      fileName: 'a.png',
      mimeType: 'image/png',
      size: 3,
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await repository.uploadMedia(
      ticket: ticket,
      bytes: const [1, 2, 3],
      size: 3,
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    expect(uploadedContentType, 'image/png');
  });

  test('媒体完成返回 503 时重试且禁止直接 DELETE 媒体', () async {
    var completeCalls = 0;
    var deleteCalls = 0;
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/media/upload-token') {
          return http.Response(
            jsonEncode({
              'media_id': 'media-2',
              'upload_url': 'https://upload.example/object',
              'upload_method': 'PUT',
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            }),
            201,
          );
        }
        if (request.url.host == 'upload.example') {
          return http.Response('', 200);
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/media/media-2/complete') {
          completeCalls += 1;
          return http.Response('{"code":"STORAGE_UNAVAILABLE"}', 503);
        }
        if (request.method == 'DELETE' &&
            request.url.path == '/api/v1/media/media-2') {
          deleteCalls += 1;
          return http.Response('', 204);
        }
        return http.Response('not found', 404);
      }),
    );
    final repository = ApiPublishRepository(client);

    final ticket = await repository.requestMediaUpload(
      fileName: 'a.png',
      mimeType: 'image/png',
      size: 3,
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    await expectLater(
      repository.uploadMedia(
        ticket: ticket,
        bytes: const [1, 2, 3],
        size: 3,
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      throwsA(isA<ApiException>()),
    );
    expect(completeCalls, 3);
    expect(deleteCalls, 0);
  });

  test('PUT 源文件失败时应调用 DELETE 清理 pending 媒体', () async {
    var deleteCalls = 0;
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/media/upload-token') {
          return http.Response(
            jsonEncode({
              'media_id': 'media-put-fail',
              'upload_url': 'https://upload.example/object',
              'upload_method': 'PUT',
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            }),
            201,
          );
        }
        if (request.url.host == 'upload.example') {
          return http.Response('Internal error', 500);
        }
        if (request.method == 'DELETE' &&
            request.url.path == '/api/v1/media/media-put-fail') {
          deleteCalls += 1;
          return http.Response('', 204);
        }
        return http.Response('not found', 404);
      }),
    );
    final repository = ApiPublishRepository(client);
    final ticket = await repository.requestMediaUpload(
      fileName: 'a.png',
      mimeType: 'image/png',
      size: 3,
      sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    await expectLater(
      repository.uploadMedia(
        ticket: ticket,
        bytes: const [1, 2, 3],
        size: 3,
        sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      throwsA(isA<ApiException>()),
    );
    expect(deleteCalls, 1);
  });

  test('POST /complete 明确 400 校验失败时清理媒体资产', () async {
    var deleteCalls = 0;
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/media/upload-token') {
          return http.Response(
            jsonEncode({
              'media_id': 'media-400',
              'upload_url': 'https://upload.example/object',
              'upload_method': 'PUT',
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            }),
            201,
          );
        }
        if (request.url.host == 'upload.example') {
          return http.Response('', 200);
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/media/media-400/complete') {
          return http.Response('{"code":"INVALID_MEDIA"}', 400);
        }
        if (request.method == 'DELETE' &&
            request.url.path == '/api/v1/media/media-400') {
          deleteCalls += 1;
          return http.Response('', 204);
        }
        return http.Response('not found', 404);
      }),
    );
    final repository = ApiPublishRepository(client);
    final ticket = await repository.requestMediaUpload(
      fileName: 'a.png',
      mimeType: 'image/png',
      size: 3,
      sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    await expectLater(
      repository.uploadMedia(
        ticket: ticket,
        bytes: const [1, 2, 3],
        size: 3,
        sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      throwsA(isA<ApiException>()),
    );
    expect(deleteCalls, 1);
  });

  test('completeMedia 允许直接验证并完成已有媒体（重试与草稿恢复链路）', () async {
    late http.Request completeRequest;
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example'),
      client: MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/media/media-resume-1/complete') {
          completeRequest = request;
          return http.Response('{"id":"media-resume-1","status":"ready"}', 200);
        }
        return http.Response('not found', 404);
      }),
    );
    final repository = ApiPublishRepository(client);

    final res = await repository.completeMedia(
      mediaId: 'media-resume-1',
      size: 1024,
      sha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );

    expect(completeRequest.method, 'POST');
    expect(completeRequest.url.path, '/api/v1/media/media-resume-1/complete');
    expect(res['status'], 'ready');
  });
}
