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
}
