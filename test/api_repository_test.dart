import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/api_repositories.dart';

void main() {
  test('ApiFeedRepository 映射列表和游标', () async {
    Uri? requestedUri;
    final repository = ApiFeedRepository(
      ApiClient(
        baseUri: Uri.parse('https://example.com'),
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response.bytes(
            utf8.encode(
              '''{"items":[{"id":"p1","author":{"id":"u1","username":"user","nickname":"用户"},"community":{"id":"c1","slug":"campus","name":"校园"},"type":"normal","title":"标题","content_preview":"正文","comment_count":2,"like_count":3,"view_count":4,"created_at":"2026-08-22T12:00:00Z"}],"next_cursor":"cursor-1","has_more":true}''',
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    final page = await repository.getFeed(
      limit: 20,
      postType: 'game_share',
      hasMedia: true,
    );

    expect(page.items.single.id, 'p1');
    expect(page.items.single.author?.nickname, '用户');
    expect(page.nextCursor, 'cursor-1');
    expect(page.hasMore, isTrue);
    expect(requestedUri?.queryParameters['post_type'], 'game_share');
    expect(requestedUri?.queryParameters['has_media'], 'true');
  });

  test('ApiPostRepository 把 404 映射成空详情', () async {
    final repository = ApiPostRepository(
      ApiClient(
        baseUri: Uri.parse('https://example.com'),
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode('{"code":"NOT_FOUND","message":"不存在"}'),
            404,
          ),
        ),
      ),
    );
    expect(await repository.getPost('missing'), isNull);
  });
}
