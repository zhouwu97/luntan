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

  test('ApiUserRepository 映射公开帖子真实点赞和浏览量', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            '{"items":[{"id":"post-1","title":"真实帖子","content_preview":"正文","community_name":"评测区","comment_count":5,"like_count":37,"view_count":321,"created_at":"2026-08-24T20:00:00Z"}],"has_more":false}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    final page = await ApiUserRepository(client).listPosts('u1');

    expect(page.items.single.likeCount, 37);
    expect(page.items.single.viewCount, 321);
    expect(page.items.single.commentCount, 5);
    client.close();
  });

  test('ApiUserRepository 将游客经验保留但等级永久锁定为 0', () async {
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            '{"id":"guest-1","username":"guest_1","nickname":"游客","bio":"","account_type":"guest","level":1,"experience":860,"growth":{"level":1,"experience":860,"level_start_experience":600,"next_level_experience":1000,"experience_in_level":260,"experience_required_in_level":400,"level_progress":0.65,"level_locked":false},"trust_level":"new","status":"active","post_count":0,"follower_count":0,"following_count":0,"created_at":"2026-08-24T20:00:00Z","viewer_state":{}}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    final profile = await ApiUserRepository(client).getProfile('guest-1');

    expect(profile?.experience, 860);
    expect(profile?.level, 0);
    expect(profile?.growth?.level, 0);
    expect(profile?.growth?.levelLocked, isTrue);
    expect(profile?.growth?.nextLevelExperience, isNull);
    expect(profile?.growth?.progress, isNull);
    client.close();
  });

  test('ProfileRepository 将我的评论解析为收到回复的帖子记录', () async {
    Uri? requestedUri;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(
          utf8.encode(
            '{"items":[{"id":"post-1","title":"帖子标题","content_preview":"正文预览","community_id":"c1","community_name":"大型拆箱","comment_count":3,"like_count":2,"bookmark_count":1,"published_at":"2026-08-24T20:00:00Z","activity_at":"2026-08-24T23:20:00Z"}],"next_cursor":"cursor-1","has_more":true}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final page = await ProfileRepository(client).list('comments');

    final item = page.items.single;
    expect(item.id, 'post-1');
    expect(item.title, '帖子标题');
    expect(item.commentCount, 3);
    expect(item.activityAt, DateTime.parse('2026-08-24T23:20:00Z'));
    expect(requestedUri?.path, '/api/v1/me/comments');
    client.close();
  });

  test('ProfileRepository 为首页个人 Feed 请求完整帖子摘要', () async {
    Uri? requestedUri;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(
          utf8.encode(
            '{"items":[{"id":"post-2","author":{"id":"u1","username":"user","nickname":"用户","level":6},"community":{"id":"c1","slug":"unboxing","name":"大型拆箱"},"type":"normal","title":"帖子标题","content":"完整正文","comment_count":4,"like_count":2,"bookmark_count":1,"view_count":99,"created_at":"2026-08-24T20:00:00Z","published_at":"2026-08-24T20:00:00Z","viewer_state":{"has_liked":true}}],"has_more":false}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final page = await ProfileRepository(
      client,
    ).list('posts', includeDetails: true);

    expect(requestedUri?.queryParameters['include_details'], '1');
    expect(page.items.single.contentPreview, '完整正文');
    expect(page.items.single.authorNickname, '用户');
    expect(page.items.single.viewerState?.hasLiked, isTrue);
    client.close();
  });
}
