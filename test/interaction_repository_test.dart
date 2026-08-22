import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/interaction_repository.dart';

void main() {
  test(
    'ApiInteractionRepository maps active and inactive actions to PUT/DELETE',
    () async {
      final methods = <String>[];
      final client = ApiClient(
        baseUri: Uri.parse('https://example.com'),
        client: MockClient((request) async {
          methods.add('${request.method} ${request.url.path}');
          return http.Response('{"active":true}', 200);
        }),
      );
      final repository = ApiInteractionRepository(client);

      await repository.setPostLike(postId: 'p1', active: true);
      await repository.setPostLike(postId: 'p1', active: false);
      await repository.setCommunityMembership(communityId: 'c1', active: true);

      expect(methods, [
        'PUT /api/v1/posts/p1/like',
        'DELETE /api/v1/posts/p1/like',
        'PUT /api/v1/communities/c1/membership',
      ]);
      client.close();
    },
  );
}
