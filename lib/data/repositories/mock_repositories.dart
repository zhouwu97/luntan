import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../api/api_client.dart';
import '../api/appeal_repository.dart';
import '../api/comment_repository.dart';
import '../api/bookmark_repository.dart';
import '../api/interaction_repository.dart';
import '../api/publish_repository.dart';
import '../api/platform_repository.dart';
import '../mock_forum_data.dart';

/// 离线预览也使用正式通知页，不再回退到旧通知抽屉。
class MockPlatformRepository extends PlatformRepository {
  MockPlatformRepository({ForumStore? store})
    : _store = store ?? ForumStore.seeded(),
      super(ApiClient(baseUri: Uri.parse('https://mock.invalid')));

  final ForumStore _store;
  final List<ForumNotification> _notifications = <ForumNotification>[];

  static const _rankingToys = <SearchToy>[
    SearchToy(
      id: 'toy-butter-2',
      rank: 1,
      name: '黄油小姐 二代',
      merchant: 'COC',
      releaseYear: 2025,
      description: '奶香材质、软糯包裹，适合新手入门。',
      tags: ['奶香材质', '软糯包裹', '新手友好'],
      assetKey: 'thumb_01.webp',
      wantCount: 401,
      ratingCount: 17,
      score: 8.7,
      category: 'cup',
      segments: ['beginner'],
    ),
    SearchToy(
      id: 'toy-yingchuan-2',
      rank: 2,
      name: '樱川爱 二代',
      merchant: 'TMT',
      releaseYear: 2026,
      description: '细密颗粒和慢玩结构，适合循序渐进。',
      tags: ['细密颗粒', '肉褶延续', '极致慢玩'],
      assetKey: 'thumb_02.webp',
      wantCount: 401,
      ratingCount: 17,
      score: 9.9,
      category: 'cup',
      segments: ['beginner'],
    ),
    SearchToy(
      id: 'toy-yutou',
      rank: 3,
      name: '鱼头',
      merchant: 'TMT',
      releaseYear: 2025,
      description: '猎奇造型与高性价比兼顾。',
      tags: ['猎奇', '高性价比', '传说神器'],
      assetKey: 'thumb_03.webp',
      wantCount: 497,
      ratingCount: 90,
      score: 9.1,
      category: 'cup',
      segments: ['advanced'],
    ),
    SearchToy(
      id: 'toy-yuanqi',
      rank: 4,
      name: '元气教练',
      merchant: 'TMT',
      releaseYear: 2025,
      description: '软硬适中的训练向结构。',
      tags: ['强烈挤压', '脂软工艺', '后入抓握'],
      assetKey: 'thumb_04.webp',
      wantCount: 284,
      ratingCount: 60,
      score: 9.3,
      category: 'cup',
      segments: ['advanced'],
    ),
    SearchToy(
      id: 'toy-shendai',
      rank: 5,
      name: '神代雪乃',
      merchant: 'TMT',
      releaseYear: 2025,
      description: '顶级材料和一字开腿结构。',
      tags: ['顶级材料', '一字开腿', '冷门神作'],
      assetKey: 'thumb_05.jpg',
      wantCount: 148,
      ratingCount: 110,
      score: 9.8,
      category: 'half_body',
      segments: ['beginner', 'advanced'],
    ),
  ];

  static List<SearchToy> get rankingToys => _rankingToys;

  @override
  Future<NotificationPage> listNotifications({
    String? cursor,
    int limit = 20,
    NotificationCategory category = NotificationCategory.all,
  }) async {
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit).clamp(0, _notifications.length).toInt();
    return NotificationPage(
      items: _notifications.sublist(start, end),
      nextCursor: end < _notifications.length ? '$end' : null,
      hasMore: end < _notifications.length,
    );
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    for (final item in _notifications) {
      if (item.id == notificationId) item.isRead = true;
    }
  }

  @override
  Future<void> markAllNotificationsRead() async {
    for (final item in _notifications) {
      item.isRead = true;
    }
  }

  @override
  Future<int> unreadNotificationCount() async =>
      _notifications.where((item) => !item.isRead).length;

  @override
  Future<SearchResult> search(
    String query, {
    String type = 'all',
    int limit = 20,
    String? cursor,
  }) async {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty || cursor != null) return const SearchResult();
    bool include(String value) => type == 'all' || type == value;
    if (!include('posts') &&
        !include('users') &&
        !include('communities') &&
        !include('toys')) {
      return const SearchResult();
    }

    final toys = include('toys')
        ? _rankingToys
              .where(
                (toy) =>
                    '${toy.name} ${toy.merchant} ${toy.description} ${toy.tags.join(' ')}'
                        .toLowerCase()
                        .contains(keyword),
              )
              .take(limit.clamp(1, 50).toInt())
              .toList()
        : const <SearchToy>[];
    final posts = include('posts')
        ? _store
              .search(query)
              .take(limit.clamp(1, 50).toInt())
              .map(
                (post) => SearchPost(
                  id: post.id,
                  title: post.title,
                  contentPreview: post.content,
                  communityId: post.communityId,
                  communityName: post.community?.name ?? post.tag,
                  createdAt: post.createdAt,
                  authorId: post.authorId,
                  authorName: post.author?.nickname ?? '用户',
                  authorLevel: post.author?.level ?? 1,
                  commentCount: post.commentCount,
                  likeCount: post.likeCount,
                  viewCount: post.viewCount,
                ),
              )
              .toList()
        : const <SearchPost>[];
    final users = include('users')
        ? _store
              .searchUsers(query)
              .take(limit.clamp(1, 50).toInt())
              .map(
                (user) => SearchUser(
                  id: user.id,
                  username: user.username,
                  nickname: user.nickname,
                ),
              )
              .toList()
        : const <SearchUser>[];
    final communities = include('communities')
        ? _store
              .searchCommunities(query)
              .take(limit.clamp(1, 50).toInt())
              .map(
                (community) => SearchCommunity(
                  id: community.id,
                  slug: community.slug,
                  name: community.name,
                  description: community.description,
                  followerCount: community.followerCount,
                ),
              )
              .toList()
        : const <SearchCommunity>[];
    return SearchResult(
      toys: toys,
      posts: posts,
      users: users,
      communities: communities,
    );
  }
}

class MockAppealRepository extends AppealRepository {
  MockAppealRepository()
    : super(ApiClient(baseUri: Uri.parse('https://mock.invalid')));

  @override
  Future<AppealPage> listAppeals({String? status, int limit = 20}) async =>
      const AppealPage(items: []);

  @override
  Future<ModerationAppealPage> listModerationAppeals({
    String? status,
    int limit = 20,
  }) async => const ModerationAppealPage(items: []);
}

class MockCommunityRepository implements CommunityRepository {
  MockCommunityRepository({ForumStore? store})
    : _store = store ?? ForumStore.seeded();

  final ForumStore _store;

  @override
  Future<List<Community>> getCommunities({
    String? categoryId,
    CommunityStatus? status,
    bool? canPublish,
  }) async {
    return _store.communities.where((community) {
      final matchesCategory =
          categoryId == null || community.categoryId == categoryId;
      final matchesStatus = status == null || community.status == status;
      final matchesPublishPolicy = canPublish != true || community.canPublish;
      return matchesCategory && matchesStatus && matchesPublishPolicy;
    }).toList();
  }

  @override
  Future<Community?> getCommunity(String id) async {
    for (final community in _store.communities) {
      if (community.id == id) return community;
    }
    return null;
  }
}

class MockFeedRepository implements FeedRepository, QueryableFeedRepository {
  MockFeedRepository({ForumStore? store, int pageSize = 20})
    : _store = store ?? ForumStore.seeded(),
      _pageSize = pageSize.clamp(1, 50).toInt();

  final ForumStore _store;
  final int _pageSize;

  @override
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20}) async {
    return getFeed(cursor: cursor, limit: limit);
  }

  @override
  Future<FeedPage> getFeed({
    String? cursor,
    int limit = 20,
    String? communityId,
    String sort = 'latest',
    LatestOrder latestOrder = LatestOrder.comment,
    String? postType,
    bool? hasMedia,
    String? topic,
  }) async {
    final normalizedLimit = limit.clamp(1, _pageSize).toInt();
    final posts = [..._store.posts]
      ..removeWhere(
        (post) =>
            post.publicationStatus != PublicationStatus.published ||
            post.moderationStatus != ModerationStatus.normal,
      )
      ..removeWhere(
        (post) => communityId != null && post.communityId != communityId,
      );

    if (sort == 'recommended') {
      posts.removeWhere((post) => !post.isRecommended);
    }

    posts.sort((a, b) {
      final int by;
      switch (sort) {
        case 'recommended':
          final posA = a.recommendationPosition ?? 999999;
          final posB = b.recommendationPosition ?? 999999;
          final byPos = posA.compareTo(posB);
          by = byPos != 0
              ? byPos
              : (b.publishedAt ?? b.createdAt).compareTo(
                  a.publishedAt ?? a.createdAt,
                );
        case 'featured':
          by = (b.isFeatured ? 1 : 0).compareTo(a.isFeatured ? 1 : 0);
        case 'hot':
          by = b.commentCount.compareTo(a.commentCount);
        default:
          if (latestOrder == LatestOrder.comment) {
            final timeA = a.activityAt ?? a.publishedAt ?? a.createdAt;
            final timeB = b.activityAt ?? b.publishedAt ?? b.createdAt;
            by = timeB.compareTo(timeA);
          } else {
            by = (b.publishedAt ?? b.createdAt).compareTo(
              a.publishedAt ?? a.createdAt,
            );
          }
      }
      return by == 0 ? b.id.compareTo(a.id) : by;
    });
    final start = int.tryParse(cursor ?? '') ?? 0;
    if (start >= posts.length) return const FeedPage(items: [], hasMore: false);
    final end = (start + normalizedLimit).clamp(0, posts.length).toInt();
    return FeedPage(
      items: posts.sublist(start, end),
      nextCursor: end < posts.length ? '$end' : null,
      hasMore: end < posts.length,
    );
  }
}

class MockPostRepository implements PostRepository, PostMutationRepository {
  MockPostRepository({ForumStore? store})
    : _store = store ?? ForumStore.seeded();

  final ForumStore _store;

  @override
  Future<PostDetail?> getPost(String id) async {
    for (final post in _store.posts) {
      if (post.id == id &&
          post.publicationStatus == PublicationStatus.published &&
          post.moderationStatus == ModerationStatus.normal) {
        return PostDetail(post: post);
      }
    }
    return null;
  }

  @override
  Future<Post> updatePost({
    required String postId,
    required String communityId,
    required String type,
    required String title,
    required String content,
    List<String> mediaIds = const [],
    String? topic,
  }) async {
    final post = _store.posts.firstWhere((item) => item.id == postId);
    post.title = title;
    post.content = content;
    _store.touch();
    return post;
  }

  @override
  Future<void> deletePost(String postId) async {
    _store.posts.removeWhere((post) => post.id == postId);
  }
}

class MockBookmarkRepository implements BookmarkRepository {
  MockBookmarkRepository({ForumStore? store})
    : _store = store ?? ForumStore.seeded() {
    final now = DateTime.now().toUtc();
    _folders['default'] = BookmarkFolder(
      id: 'default',
      name: '默认收藏夹',
      isDefault: true,
      sortOrder: 0,
      itemCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    _items['default'] = _store.bookmarkedPosts.map((post) => post.id).toSet();
    _refreshCounts();
  }

  final ForumStore _store;
  final Map<String, BookmarkFolder> _folders = <String, BookmarkFolder>{};
  final Map<String, Set<String>> _items = <String, Set<String>>{};
  int _nextFolder = 1;

  @override
  Future<BookmarkFolderPage> listFolders({
    String? cursor,
    int limit = 20,
  }) async {
    final values = _folders.values.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit.clamp(1, 50)).clamp(0, values.length).toInt();
    return BookmarkFolderPage(
      items: values.sublist(start, end),
      nextCursor: end < values.length ? '$end' : null,
      hasMore: end < values.length,
    );
  }

  @override
  Future<BookmarkFolder> createFolder(
    String name, {
    String? idempotencyKey,
  }) async {
    final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty || normalized.runes.length > 40) {
      throw const ApiException(type: ApiErrorType.unknown, message: '收藏夹名称不合法');
    }
    if (_folders.values.any(
      (folder) => folder.name.toLowerCase() == normalized.toLowerCase(),
    )) {
      throw const ApiException(
        type: ApiErrorType.conflict,
        message: '收藏夹名称已存在',
      );
    }
    final now = DateTime.now().toUtc();
    final id = 'folder-${_nextFolder++}';
    final folder = BookmarkFolder(
      id: id,
      name: normalized,
      isDefault: false,
      sortOrder: _folders.length,
      itemCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    _folders[id] = folder;
    _items[id] = <String>{};
    return folder;
  }

  @override
  Future<BookmarkFolder> renameFolder(String folderId, String name) async {
    final folder = _folders[folderId];
    if (folder == null) {
      throw const ApiException(type: ApiErrorType.notFound, message: '收藏夹不存在');
    }
    if (folder.isDefault) {
      throw const ApiException(
        type: ApiErrorType.unknown,
        message: '默认收藏夹不能重命名',
      );
    }
    final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_folders.values.any(
      (item) =>
          item.id != folderId &&
          item.name.toLowerCase() == normalized.toLowerCase(),
    )) {
      throw const ApiException(
        type: ApiErrorType.conflict,
        message: '收藏夹名称已存在',
      );
    }
    final updated = folder.copyWith(name: normalized);
    _folders[folderId] = updated;
    return updated;
  }

  @override
  Future<BookmarkFolder> reorderFolder(String folderId, int sortOrder) async {
    final folder = _folders[folderId];
    if (folder == null) {
      throw const ApiException(type: ApiErrorType.notFound, message: '收藏夹不存在');
    }
    final updated = folder.copyWith(sortOrder: sortOrder);
    _folders[folderId] = updated;
    return updated;
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    final folder = _folders[folderId];
    if (folder == null) {
      throw const ApiException(type: ApiErrorType.notFound, message: '收藏夹不存在');
    }
    if (folder.isDefault) {
      throw const ApiException(
        type: ApiErrorType.unknown,
        message: '默认收藏夹不能删除',
      );
    }
    final defaultItems = _items['default']!;
    for (final postId in _items[folderId] ?? <String>{}) {
      final elsewhere = _items.entries.any(
        (entry) => entry.key != folderId && entry.value.contains(postId),
      );
      if (!elsewhere) defaultItems.add(postId);
    }
    _items.remove(folderId);
    _folders.remove(folderId);
    _refreshCounts();
  }

  @override
  Future<BookmarkPostPage> listFolderPosts(
    String folderId, {
    String? cursor,
    int limit = 20,
  }) async {
    final ids = _items[folderId] ?? <String>{};
    final posts = _store.posts.where((post) => ids.contains(post.id)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit.clamp(1, 50)).clamp(0, posts.length).toInt();
    return BookmarkPostPage(
      items: posts
          .sublist(start, end)
          .map(
            (post) => BookmarkPost(
              id: post.id,
              title: post.title,
              contentPreview: post.content,
              communityId: post.communityId,
              communityName: post.community?.name ?? post.section.label,
              commentCount: post.commentCount,
              likeCount: post.likeCount,
              bookmarkCount: post.bookmarkCount,
              createdAt: post.createdAt,
            ),
          )
          .toList(),
      nextCursor: end < posts.length ? '$end' : null,
      hasMore: end < posts.length,
    );
  }

  @override
  Future<BookmarkSelection> getPostFolders(String postId) async {
    final selected = _items.entries
        .where((entry) => entry.value.contains(postId))
        .map((entry) => entry.key)
        .toList();
    final folders =
        _folders.values
            .map(
              (folder) =>
                  folder.copyWith(selected: selected.contains(folder.id)),
            )
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return BookmarkSelection(folders: folders, selectedFolderIds: selected);
  }

  @override
  Future<BookmarkSelection> setPostFolders(
    String postId,
    List<String> folderIds,
  ) async {
    final selected = folderIds.toSet();
    for (final folderId in selected) {
      if (!_folders.containsKey(folderId)) {
        throw const ApiException(
          type: ApiErrorType.notFound,
          message: '收藏夹不存在',
        );
      }
    }
    for (final items in _items.values) {
      items.remove(postId);
    }
    for (final folderId in selected) {
      _items[folderId]!.add(postId);
    }
    _refreshCounts();
    return getPostFolders(postId);
  }

  void _refreshCounts() {
    for (final entry in _folders.entries) {
      _folders[entry.key] = entry.value.copyWith(
        itemCount: _items[entry.key]?.length ?? 0,
      );
    }
  }
}

/// Mock 模式也走与 API 模式相同的 Repository/Controller 链路，避免页面
/// 通过 ForumStore 直接写入而掩盖真实模式的问题。
class MockCommentRepository
    implements CommentRepository, CommentMutationRepository {
  MockCommentRepository({ForumStore? store})
    : _store = store ?? ForumStore.seeded();

  final ForumStore _store;

  @override
  Future<CommentPage> listComments({
    required String postId,
    int limit = 20,
    int offset = 0,
    CommentSort? sort,
    String? authorId,
  }) async {
    final all = [...(_store.commentsByPost[postId] ?? const <Comment>[])]
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime == 0 ? a.id.compareTo(b.id) : byTime;
      });
    final children = <String, List<Comment>>{};
    for (final comment in all) {
      final parentId = comment.parentId;
      if (parentId == null || parentId.isEmpty) continue;
      children.putIfAbsent(parentId, () => <Comment>[]).add(comment);
    }
    final floors = <Comment>[];
    var floorNo = 0;
    for (final comment in all) {
      if (comment.parentId != null) continue;
      if (authorId != null && comment.authorId != authorId) continue;
      floorNo += 1;
      final replies = children[comment.id] ?? const <Comment>[];
      floors.add(
        _copyComment(
          comment,
          floor: floorNo,
          replyCount: replies.length,
          replyPreview: replies.take(3).toList(),
        ),
      );
    }
    switch (sort ?? CommentSort.asc) {
      case CommentSort.hot:
        floors.sort((a, b) {
          final byLikes = b.likeCount.compareTo(a.likeCount);
          return byLikes == 0
              ? (a.floor ?? 0).compareTo(b.floor ?? 0)
              : byLikes;
        });
      case CommentSort.desc:
        floors.sort((a, b) => (b.floor ?? 0).compareTo(a.floor ?? 0));
      case CommentSort.asc:
        break;
    }
    final safeOffset = offset.clamp(0, floors.length).toInt();
    final end = (safeOffset + limit.clamp(1, 50)).clamp(0, floors.length).toInt();
    return CommentPage(
      items: floors.sublist(safeOffset, end),
      hasMore: end < floors.length,
      total: floors.length,
    );
  }

  Comment _copyComment(
    Comment comment, {
    int? floor,
    int? replyCount,
    List<Comment> replyPreview = const [],
  }) => Comment(
    id: comment.id,
    postId: comment.postId,
    authorId: comment.authorId,
    author: comment.author,
    rootId: comment.rootId,
    parentId: comment.parentId,
    replyToUserId: comment.replyToUserId,
    replyToUser: comment.replyToUser,
    content: comment.content,
    media: comment.media,
    stickerId: comment.stickerId,
    likeCount: comment.likeCount,
    isLiked: comment.isLiked,
    dislikeCount: comment.dislikeCount,
    isDisliked: comment.isDisliked,
    floor: floor,
    replyPreview: replyPreview,
    replyCount: replyCount ?? comment.replyCount,
    publicationStatus: comment.publicationStatus,
    moderationStatus: comment.moderationStatus,
    createdAt: comment.createdAt,
    updatedAt: comment.updatedAt,
  );

  @override
  Future<CommentPage> listReplies({
    required String commentId,
    String? cursor,
    int limit = 20,
  }) async {
    final all = _store.commentsByPost.values.expand((items) => items).toList();
    Comment? source;
    for (final item in all) {
      if (item.id == commentId) {
        source = item;
        break;
      }
    }
    if (source == null) return const CommentPage(items: []);
    final rootId = source.rootId ?? source.id;
    final sorted =
        all
            .where((item) => item.rootId == rootId && item.id != commentId)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit.clamp(1, 50)).clamp(0, sorted.length).toInt();
    return CommentPage(
      items: sorted.sublist(start, end),
      nextCursor: end < sorted.length ? '$end' : null,
      hasMore: end < sorted.length,
    );
  }

  @override
  Future<Comment> createComment({
    required String postId,
    required String content,
    String? parentId,
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
  }) async {
    final post = _store.posts.firstWhere((item) => item.id == postId);
    return _store.addComment(
      post,
      content,
      parentId: parentId,
      replyToUserId: replyToUserId,
      mediaIds: mediaIds,
      stickerId: stickerId,
    );
  }

  @override
  Future<Comment> createReply({
    required String commentId,
    required String content,
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
  }) async {
    final source = _store.commentsByPost.values
        .expand((items) => items)
        .firstWhere((item) => item.id == commentId);
    final post = _store.posts.firstWhere((item) => item.id == source.postId);
    return _store.addComment(
      post,
      content,
      parentId: source.id,
      replyToUserId: replyToUserId,
      mediaIds: mediaIds,
      stickerId: stickerId,
    );
  }

  @override
  Future<void> deleteComment(String commentId) async {
    for (final post in _store.posts) {
      final comments = _store.commentsByPost[post.id];
      final comment = comments?.cast<Comment?>().firstWhere(
        (item) => item?.id == commentId,
        orElse: () => null,
      );
      if (comment != null) {
        _store.deleteComment(post, comment);
        return;
      }
    }
  }

  @override
  Future<Comment> updateComment({
    required String commentId,
    required String content,
  }) async {
    for (final comments in _store.commentsByPost.values) {
      final index = comments.indexWhere((item) => item.id == commentId);
      if (index >= 0) {
        final old = comments[index];
        final updated = Comment(
          id: old.id,
          postId: old.postId,
          authorId: old.authorId,
          author: old.author,
          rootId: old.rootId,
          parentId: old.parentId,
          replyToUserId: old.replyToUserId,
          content: content,
          likeCount: old.likeCount,
          replyCount: old.replyCount,
          publicationStatus: old.publicationStatus,
          moderationStatus: old.moderationStatus,
          createdAt: old.createdAt,
          updatedAt: DateTime.now(),
        );
        comments[index] = updated;
        return updated;
      }
    }
    throw StateError('comment not found');
  }
}

class MockInteractionRepository implements InteractionRepository {
  @override
  Future<void> setPostLike({
    required String postId,
    required bool active,
  }) async {}

  @override
  Future<void> setCommentLike({
    required String commentId,
    required bool active,
  }) async {}

  @override
  Future<void> setCommentDislike({
    required String commentId,
    required bool active,
  }) async {}

  @override
  Future<void> setBookmark({
    required String postId,
    required bool active,
  }) async {}

  @override
  Future<void> setUserFollow({
    required String userId,
    required bool active,
  }) async {}

  @override
  Future<void> setCommunityFollow({
    required String communityId,
    required bool active,
  }) async {}

  @override
  Future<void> setCommunityMembership({
    required String communityId,
    required bool active,
  }) async {}
}

class MockPublishRepository implements PublishRepository {
  MockPublishRepository({required ForumStore store}) : _store = store;

  final ForumStore _store;

  @override
  Future<Map<String, dynamic>> createPost({
    required String communityId,
    required String type,
    required String title,
    required String content,
    required String idempotencyKey,
    List<String> mediaIds = const [],
    String? topic,
  }) async {
    final section = ForumSection.values.firstWhere(
      (item) => item.communityId == communityId,
      orElse: () => ForumSection.unboxing,
    );
    _store.addPost(
      PostDraft(
        title: title,
        body: content,
        section: section,
        type: type,
        topic: topic,
        isPoll: type == 'poll',
      ),
    );
    return {'id': _store.posts.first.id, 'idempotency_key': idempotencyKey};
  }

  @override
  Future<MediaUploadTicket> requestMediaUpload({
    required String fileName,
    required String mimeType,
    required int size,
    required String sha256,
    int width = 0,
    int height = 0,
  }) => throw const PublishException('Mock 模式不需要上传媒体凭证');

  @override
  Future<Map<String, dynamic>> uploadMedia({
    required MediaUploadTicket ticket,
    required List<int> bytes,
    required int size,
    required String sha256,
  }) => throw const PublishException('Mock 模式不需要上传媒体');

  @override
  Future<Map<String, dynamic>> completeMedia({
    required String mediaId,
    required int size,
    required String sha256,
  }) => throw const PublishException('Mock 模式不需要确认媒体');

  @override
  Future<void> deleteMedia(String mediaId) async {}
}
