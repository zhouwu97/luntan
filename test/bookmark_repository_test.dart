import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luntan/data/api/api_client.dart';
import 'package:luntan/data/api/bookmark_repository.dart';

void main() {
  test(
    'ApiBookmarkRepository maps folder CRUD and multi-folder selection',
    () async {
      final requests = <String>[];
      final client = ApiClient(
        baseUri: Uri.parse('https://example.com'),
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.url.path == '/api/v1/me/bookmark-folders') {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'items': [
                    {
                      'id': 'default',
                      'name': '默认收藏夹',
                      'is_default': true,
                      'sort_order': 0,
                      'item_count': 2,
                      'created_at': '2026-08-24T00:00:00Z',
                      'updated_at': '2026-08-24T00:00:00Z',
                    },
                  ],
                  'has_more': false,
                }),
              ),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          if (request.method == 'GET') {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'folders': [
                    {
                      'id': 'default',
                      'name': '默认收藏夹',
                      'is_default': true,
                      'sort_order': 0,
                      'item_count': 2,
                      'selected': true,
                    },
                  ],
                  'folder_ids': ['default'],
                }),
              ),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'active': true,
                'folder_ids': ['default', 'desk'],
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final repository = ApiBookmarkRepository(client);

      final folders = await repository.listFolders();
      final selection = await repository.setPostFolders('p1', [
        'default',
        'desk',
      ]);

      expect(folders.items.single.name, '默认收藏夹');
      expect(selection.selectedFolderIds, ['default', 'desk']);
      expect(requests, [
        'GET /api/v1/me/bookmark-folders',
        'PUT /api/v1/posts/p1/bookmark-folders',
        'GET /api/v1/posts/p1/bookmark-folders',
      ]);
      client.close();
    },
  );
}
