import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/ranking_repository.dart';

class _StubClient extends ApiClient {
  _StubClient() : super(baseUri: Uri.parse('http://127.0.0.1:9'));

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path.endsWith('/comments')) {
      return {
        'items': [
          {
            'id': 'byj-review-00000717',
            'content': 'test',
            'like_count': 9,
            'created_at': '2026-07-16T13:19:21.883Z',
            'reply_count': 8,
            'author': {
              'id': 'byj-user-102',
              'username': 'byj_102',
              'nickname': 'reviewer',
              'level': 5,
              'avatar_url': 'http://127.0.0.1:8899/ranking/beiyoujiang/byj_avatar102.webp',
            },
            'viewer_state': {'has_liked': false},
            'media': [
              {
                'id': 'm1',
                'url': 'http://127.0.0.1:8899/ranking/beiyoujiang/byj_rev1_0.webp',
                'width': 0,
                'height': 0,
                'mime_type': 'image/webp',
              },
            ],
          },
        ],
        'has_more': false,
      };
    }
    return {};
  }
}

void main() {
  test('RankingToyComment parses author avatar_url and media', () async {
    final repo = RankingRepository(_StubClient());
    final page = await repo.listComments(toyId: 'byj-76');
    final comment = page.items.single;
    expect(
      comment.avatarUrl,
      'http://127.0.0.1:8899/ranking/beiyoujiang/byj_avatar102.webp',
    );
    expect(comment.media.length, 1);
  });
}
