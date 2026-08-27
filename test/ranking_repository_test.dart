import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/ranking_repository.dart';

void main() {
  test('榜单仓储解析服务端商品、当前用户状态和评论', () async {
    Uri? requestedUri;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'id': 'toy-yingchuan-2',
            'rank': 2,
            'name': '樱川爱 二代',
            'merchant': 'TMT',
            'release_year': 2026,
            'description': '服务端详情',
            'tags': ['细密颗粒'],
            'asset_key': 'thumb_02.webp',
            'want_count': 402,
            'rating_count': 18,
            'score': 9.8,
            'viewer_state': {'wanted': true, 'owned': false, 'rating': 8},
            'comment_sort': 'latest',
            'comments': [
              {
                'id': 'comment-1',
                'content': '来自服务器的评论',
                'like_count': 8,
                'created_at': '2026-08-25T12:00:00Z',
                'author': {
                  'id': 'user-1',
                  'username': 'server-user',
                  'nickname': '服务端用户',
                  'level': 3,
                },
                'viewer_state': {'has_liked': true},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final repository = RankingRepository(client);

    final detail = await repository.detail(
      'toy-yingchuan-2',
      commentSort: 'latest',
    );

    expect(detail.toy.name, '樱川爱 二代');
    expect(detail.toy.wanted, isTrue);
    expect(detail.toy.rating, 8);
    expect(detail.comments.single.nickname, '服务端用户');
    expect(detail.comments.single.isLiked, isTrue);
    expect(requestedUri?.path, '/api/v1/ranking/toys/toy-yingchuan-2');
    expect(requestedUri?.queryParameters['comment_sort'], 'latest');
    client.close();
  });

  test('榜单互动映射到自有服务器的 REST 操作', () async {
    final requests = <String>[];
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return http.Response.bytes(
          utf8.encode(
            request.url.path.endsWith('/like')
                ? '{"active":true,"like_count":9}'
                : '{"id":"toy-yingchuan-2","rank":2,"name":"樱川爱 二代","merchant":"TMT","release_year":2026,"description":"","tags":[],"asset_key":"thumb_02.webp","want_count":402,"rating_count":18,"score":9.8,"viewer_state":{"wanted":true,"owned":true,"rating":8}}',
          ),
          request.method == 'POST' ? 201 : 200,
        );
      }),
    );
    final repository = RankingRepository(client);

    await repository.rate(toyId: 'toy-yingchuan-2', score: 8);
    await repository.createComment(toyId: 'toy-yingchuan-2', content: '真实评论');
    await repository.setCommentLike(commentId: 'comment-1', active: true);

    expect(requests, [
      'POST /api/v1/ranking/toys/toy-yingchuan-2/rating',
      'POST /api/v1/ranking/toys/toy-yingchuan-2/comments',
      'PUT /api/v1/ranking/toy-comments/comment-1/like',
    ]);
    client.close();
  });

  test('榜单评论和楼中楼使用独立游标分页接口', () async {
    final requests = <Uri>[];
    final client = ApiClient(
      baseUri: Uri.parse('https://example.com'),
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/comments')) {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'root-1',
                  'content': '一级评价',
                  'created_at': '2026-08-27T10:00:00Z',
                  'author': {'id': 'u1', 'username': 'u1'},
                  'parent_id': null,
                  'reply_count': 3,
                },
              ],
              'next_cursor': 'root-cursor',
              'has_more': true,
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'reply-1',
                'content': '回复二级评论',
                'created_at': '2026-08-27T10:01:00Z',
                'root_id': 'root-1',
                'parent_id': 'reply-0',
                'reply_to_user_id': 'u2',
                'author': {'id': 'u3', 'username': 'u3'},
              },
            ],
            'next_cursor': null,
            'has_more': false,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final repository = RankingRepository(client);

    late final RankingToyCommentPage roots;
    late final RankingToyCommentPage replies;
    try {
      roots = await repository.listComments(
        toyId: 'toy-1',
        sort: 'latest',
        limit: 1,
      );
      replies = await repository.listReplies(
        commentId: 'root-1',
        cursor: 'reply-cursor',
        limit: 1,
      );
    } catch (error) {
      if (error is ApiException) {
        fail('分页请求失败: ${error.cause}');
      }
      rethrow;
    }

    expect(roots.items.single.replyCount, 3);
    expect(roots.nextCursor, 'root-cursor');
    expect(replies.items.single.parentId, 'reply-0');
    expect(requests[0].path, '/api/v1/ranking/toys/toy-1/comments');
    expect(requests[0].queryParameters['sort'], 'latest');
    expect(requests[0].queryParameters['limit'], '1');
    expect(requests[1].path, '/api/v1/ranking/toy-comments/root-1/replies');
    expect(requests[1].queryParameters['cursor'], 'reply-cursor');
    client.close();
  });

  test('榜单对象 copyWith 保留评分分布和作者评分', () {
    final comment = RankingToyComment(
      id: 'c1',
      authorId: 'u1',
      username: 'u1',
      nickname: '用户',
      level: 4,
      content: '评价',
      likeCount: 1,
      isLiked: false,
      createdAt: DateTime.utc(2026, 8, 27),
      authorRating: 9,
    );
    const toy = RankingToy(
      id: 'toy-1',
      rank: 1,
      name: '玩具',
      merchant: '店铺',
      releaseYear: 2026,
      description: '',
      tags: [],
      assetKey: '',
      wantCount: 1,
      ratingCount: 1,
      score: 9,
      wanted: false,
      owned: false,
    );
    final detail = RankingToyDetail(
      toy: toy,
      comments: [comment],
      commentSort: 'weight',
      ratingDistribution: {9: 2},
    );

    final liked = comment.copyWith(likeCount: 2, isLiked: true);
    final updated = detail.copyWith(toy: toy);

    expect(liked.authorRating, 9);
    expect(updated.ratingDistribution, {9: 2});
  });
}
