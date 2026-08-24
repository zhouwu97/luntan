import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/api_repositories.dart';
import 'package:luntan/data/api/profile_repository.dart';
import 'package:luntan/data/api/user_repository.dart';

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

  test('ApiUserRepository 映射关注列表和 viewer 状态', () async {
    Uri? requestedUri;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(
          utf8.encode(
            '{"items":[{"id":"u2","username":"other","nickname":"另一位","viewer_state":{"is_following":true,"can_follow":true}}],"next_cursor":"cursor-2","has_more":true}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final repository = ApiUserRepository(client);
    final page = await repository.listFollowing('u1', limit: 20);

    expect(page.items.single.id, 'u2');
    expect(page.items.single.isFollowing, isTrue);
    expect(page.items.single.canFollow, isTrue);
    expect(page.nextCursor, 'cursor-2');
    expect(requestedUri?.path, '/api/v1/users/u1/following');
    client.close();
  });

  test('ProfileRepository 将我的评论解析为独立评论记录', () async {
    Uri? requestedUri;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(
          utf8.encode(
            '{"items":[{"id":"comment-1","post_id":"post-1","post_title":"帖子标题","content":"我的评论内容","community_id":"c1","community_name":"大型拆箱","created_at":"2026-08-24T23:20:00Z"}],"next_cursor":"cursor-1","has_more":true}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final page = await ProfileRepository(client).list('comments');

    final item = page.items.single as ProfileCommentItem;
    expect(item.id, 'comment-1');
    expect(item.postId, 'post-1');
    expect(item.postTitle, '帖子标题');
    expect(item.content, '我的评论内容');
    expect(requestedUri?.path, '/api/v1/me/comments');
    client.close();
  });
}
