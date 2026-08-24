import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/comment_repository.dart';

void main() {
  test('评论创建携带 Idempotency-Key', () async {
    String? key;
    final repository = ApiCommentRepository(
      ApiClient(
        baseUri: Uri.parse('https://api.example'),
        client: MockClient((request) async {
          key = request.headers['idempotency-key'];
          return http.Response.bytes(
            utf8.encode(
              '{"id":"comment-1","post_id":"post-1","content":"评论","created_at":"2026-08-24T00:00:00Z","updated_at":"2026-08-24T00:00:00Z"}',
            ),
            201,
          );
        }),
      ),
    );

    final comment = await repository.createCommentWithIdempotency(
      postId: 'post-1',
      content: '评论',
      idempotencyKey: 'comment-key-1',
    );

    expect(comment.id, 'comment-1');
    expect(key, 'comment-key-1');
  });

  test('评论响应恢复服务端 viewer 点赞状态和准确计数', () async {
    final repository = ApiCommentRepository(
      ApiClient(
        baseUri: Uri.parse('https://api.example'),
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode('''
              {"items":[{
                "id":"comment-1",
                "post_id":"post-1",
                "author":{"id":"user-1","username":"user","nickname":"用户"},
                "content":"评论",
                "like_count":11,
                "reply_count":0,
                "viewer_state":{"has_liked":true},
                "created_at":"2026-08-24T00:00:00Z",
                "updated_at":"2026-08-24T00:00:00Z"
              }],"has_more":false,"next_cursor":null}
            '''),
            200,
          ),
        ),
      ),
    );

    final page = await repository.listComments(postId: 'post-1');

    expect(page.items.single.isLiked, isTrue);
    expect(page.items.single.likeCount, 11);
  });
}
