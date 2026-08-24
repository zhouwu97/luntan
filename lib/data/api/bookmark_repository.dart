import 'api_client.dart';

class BookmarkFolder {
  const BookmarkFolder({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.sortOrder,
    required this.itemCount,
    required this.createdAt,
    required this.updatedAt,
    this.selected = false,
  });

  final String id;
  final String name;
  final bool isDefault;
  final int sortOrder;
  final int itemCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool selected;

  BookmarkFolder copyWith({
    bool? selected,
    int? itemCount,
    String? name,
    int? sortOrder,
  }) {
    return BookmarkFolder(
      id: id,
      name: name ?? this.name,
      isDefault: isDefault,
      sortOrder: sortOrder ?? this.sortOrder,
      itemCount: itemCount ?? this.itemCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      selected: selected ?? this.selected,
    );
  }
}

class BookmarkFolderPage {
  const BookmarkFolderPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<BookmarkFolder> items;
  final String? nextCursor;
  final bool hasMore;
}

class BookmarkPost {
  const BookmarkPost({
    required this.id,
    required this.title,
    required this.contentPreview,
    required this.communityId,
    required this.communityName,
    required this.commentCount,
    required this.likeCount,
    required this.bookmarkCount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String contentPreview;
  final String communityId;
  final String communityName;
  final int commentCount;
  final int likeCount;
  final int bookmarkCount;
  final DateTime createdAt;
}

class BookmarkPostPage {
  const BookmarkPostPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<BookmarkPost> items;
  final String? nextCursor;
  final bool hasMore;
}

class BookmarkSelection {
  const BookmarkSelection({
    required this.folders,
    required this.selectedFolderIds,
  });

  final List<BookmarkFolder> folders;
  final List<String> selectedFolderIds;
}

abstract interface class BookmarkRepository {
  Future<BookmarkFolderPage> listFolders({String? cursor, int limit = 20});

  Future<BookmarkFolder> createFolder(String name, {String? idempotencyKey});

  Future<BookmarkFolder> renameFolder(String folderId, String name);

  Future<BookmarkFolder> reorderFolder(String folderId, int sortOrder);

  Future<void> deleteFolder(String folderId);

  Future<BookmarkPostPage> listFolderPosts(
    String folderId, {
    String? cursor,
    int limit = 20,
  });

  Future<BookmarkSelection> getPostFolders(String postId);

  Future<BookmarkSelection> setPostFolders(
    String postId,
    List<String> folderIds,
  );
}

class ApiBookmarkRepository implements BookmarkRepository {
  ApiBookmarkRepository(this._client);

  final ApiClient _client;

  @override
  Future<BookmarkFolderPage> listFolders({
    String? cursor,
    int limit = 20,
  }) async {
    final value = await _client.getJson(
      '/api/v1/me/bookmark-folders',
      queryParameters: {
        'limit': '$limit',
        ...?(cursor == null ? null : {'cursor': cursor}),
      },
    );
    final raw = value['items'];
    final items = raw is List
        ? raw.whereType<Map>().map(_folderFromJson).toList()
        : <BookmarkFolder>[];
    return BookmarkFolderPage(
      items: items,
      nextCursor: value['next_cursor'] as String?,
      hasMore: value['has_more'] == true,
    );
  }

  @override
  Future<BookmarkFolder> createFolder(
    String name, {
    String? idempotencyKey,
  }) async {
    final value = await _client.postJson(
      '/api/v1/me/bookmark-folders',
      body: {'name': name},
      headers: {
        if (idempotencyKey != null && idempotencyKey.isNotEmpty)
          'Idempotency-Key': idempotencyKey,
      },
    );
    return _folderFromJson(value);
  }

  @override
  Future<BookmarkFolder> renameFolder(String folderId, String name) async {
    final value = await _client.patchJson(
      '/api/v1/me/bookmark-folders/$folderId',
      body: {'name': name},
    );
    return _folderFromJson(value);
  }

  @override
  Future<BookmarkFolder> reorderFolder(String folderId, int sortOrder) async {
    final value = await _client.patchJson(
      '/api/v1/me/bookmark-folders/$folderId',
      body: {'sort_order': sortOrder},
    );
    return _folderFromJson(value);
  }

  @override
  Future<void> deleteFolder(String folderId) =>
      _client.deleteJson('/api/v1/me/bookmark-folders/$folderId');

  @override
  Future<BookmarkPostPage> listFolderPosts(
    String folderId, {
    String? cursor,
    int limit = 20,
  }) async {
    final value = await _client.getJson(
      '/api/v1/me/bookmark-folders/$folderId/posts',
      queryParameters: {
        'limit': '$limit',
        ...?(cursor == null ? null : {'cursor': cursor}),
      },
    );
    final raw = value['items'];
    final items = raw is List
        ? raw.whereType<Map>().map(_postFromJson).toList()
        : <BookmarkPost>[];
    return BookmarkPostPage(
      items: items,
      nextCursor: value['next_cursor'] as String?,
      hasMore: value['has_more'] == true,
    );
  }

  @override
  Future<BookmarkSelection> getPostFolders(String postId) async {
    final value = await _client.getJson(
      '/api/v1/posts/$postId/bookmark-folders',
    );
    final raw = value['folders'];
    final folders = raw is List
        ? raw.whereType<Map>().map(_folderFromJson).toList()
        : <BookmarkFolder>[];
    final selected = value['folder_ids'];
    return BookmarkSelection(
      folders: folders,
      selectedFolderIds: selected is List
          ? selected.whereType<String>().toList()
          : folders
                .where((folder) => folder.selected)
                .map((f) => f.id)
                .toList(),
    );
  }

  @override
  Future<BookmarkSelection> setPostFolders(
    String postId,
    List<String> folderIds,
  ) async {
    final value = await _client.putJson(
      '/api/v1/posts/$postId/bookmark-folders',
      body: {'folder_ids': folderIds},
    );
    final selection = await getPostFolders(postId);
    final raw = value['folder_ids'];
    if (raw is List) {
      return BookmarkSelection(
        folders: selection.folders,
        selectedFolderIds: raw.whereType<String>().toList(),
      );
    }
    return selection;
  }

  BookmarkFolder _folderFromJson(Map raw) {
    final value = Map<String, dynamic>.from(raw);
    final now = DateTime.now().toUtc();
    return BookmarkFolder(
      id: _string(value['id']),
      name: _string(value['name']),
      isDefault: value['is_default'] == true,
      sortOrder: _int(value['sort_order']),
      itemCount: _int(value['item_count']),
      createdAt: _date(value['created_at'], now),
      updatedAt: _date(value['updated_at'], now),
      selected: value['selected'] == true,
    );
  }

  BookmarkPost _postFromJson(Map raw) {
    final value = Map<String, dynamic>.from(raw);
    final now = DateTime.now().toUtc();
    return BookmarkPost(
      id: _string(value['id']),
      title: _string(value['title']),
      contentPreview: _string(value['content_preview']),
      communityId: _string(value['community_id']),
      communityName: _string(value['community_name']),
      commentCount: _int(value['comment_count']),
      likeCount: _int(value['like_count']),
      bookmarkCount: _int(value['bookmark_count']),
      createdAt: _date(value['created_at'], now),
    );
  }

  String _string(dynamic value) => value is String ? value : '';
  int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  DateTime _date(dynamic value, DateTime fallback) =>
      value is String ? DateTime.tryParse(value) ?? fallback : fallback;
}
