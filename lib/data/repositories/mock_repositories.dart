import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../api/comment_repository.dart';
import '../api/interaction_repository.dart';
import '../api/publish_repository.dart';
import '../mock_forum_data.dart';

class MockCommunityRepository implements CommunityRepository {
  MockCommunityRepository({ForumStore? store}) : _store = store ?? ForumStore.seeded();

  final ForumStore _store;

  @override
  Future<List<Community>> getCommunities({String? categoryId, CommunityStatus? status}) async {
    return _store.communities.where((community) {
      final matchesCategory = categoryId == null || community.categoryId == categoryId;
      final matchesStatus = status == null || community.status == status;
      return matchesCategory && matchesStatus;
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
  MockFeedRepository({ForumStore? store}) : _store = store ?? ForumStore.seeded();

  final ForumStore _store;

  @override
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20}) async {
    return getFeed(cursor: cursor, limit: limit);
  }

  @override
  Future<FeedPage> getFeed({
    String? cursor,
    int limit = 20,
    String? communityId,
    String sort = 'recommended',
  }) async {
    final normalizedLimit = limit.clamp(1, 50).toInt();
    final posts = [..._store.posts]
      ..removeWhere((post) => post.publicationStatus != PublicationStatus.published || post.moderationStatus != ModerationStatus.normal)
      ..removeWhere((post) => communityId != null && post.communityId != communityId)
      ..sort((a, b) {
        final int by;
        switch (sort) {
          case 'featured':
            by = (b.isFeatured ? 1 : 0).compareTo(a.isFeatured ? 1 : 0);
          case 'hot':
            by = b.commentCount.compareTo(a.commentCount);
          default:
            by = b.createdAt.compareTo(a.createdAt);
        }
        return by == 0 ? b.id.compareTo(a.id) : by;
      });
    final start = int.tryParse(cursor ?? '') ?? 0;
    if (start >= posts.length) return const FeedPage(items: [], hasMore: false);
    final end = (start + normalizedLimit).clamp(0, posts.length).toInt();
    return FeedPage(items: posts.sublist(start, end), nextCursor: end < posts.length ? '$end' : null, hasMore: end < posts.length);
  }
}

class MockPostRepository implements PostRepository, PostMutationRepository {
  MockPostRepository({ForumStore? store}) : _store = store ?? ForumStore.seeded();

  final ForumStore _store;

  @override
  Future<PostDetail?> getPost(String id) async {
    for (final post in _store.posts) {
      if (post.id == id && post.publicationStatus == PublicationStatus.published && post.moderationStatus == ModerationStatus.normal) {
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

/// Mock 模式也走与 API 模式相同的 Repository/Controller 链路，避免页面
/// 通过 ForumStore 直接写入而掩盖真实模式的问题。
class MockCommentRepository implements CommentRepository, CommentMutationRepository {
  MockCommentRepository({ForumStore? store}) : _store = store ?? ForumStore.seeded();

  final ForumStore _store;

  @override
  Future<CommentPage> listComments({
    required String postId,
    String? cursor,
    int limit = 20,
  }) async {
    final comments = _store.commentsByPost[postId] ?? const <Comment>[];
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit.clamp(1, 50)).clamp(0, comments.length).toInt();
    return CommentPage(
      items: comments.sublist(start, end),
      nextCursor: end < comments.length ? '$end' : null,
      hasMore: end < comments.length,
    );
  }

  @override
  Future<Comment> createComment({
    required String postId,
    required String content,
    String? parentId,
    String? replyToUserId,
  }) async {
    final post = _store.posts.firstWhere((item) => item.id == postId);
    return _store.addComment(
      post,
      content,
      parentId: parentId,
      replyToUserId: replyToUserId,
    );
  }

  @override
  Future<Comment> createReply({
    required String commentId,
    required String content,
    String? replyToUserId,
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
  Future<void> setPostLike({required String postId, required bool active}) async {}

  @override
  Future<void> setCommentLike({required String commentId, required bool active}) async {}

  @override
  Future<void> setBookmark({required String postId, required bool active}) async {}

  @override
  Future<void> setUserFollow({required String userId, required bool active}) async {}

  @override
  Future<void> setCommunityFollow({required String communityId, required bool active}) async {}

  @override
  Future<void> setCommunityMembership({required String communityId, required bool active}) async {}
}

class MockPublishRepository implements PublishRepository, PollPublishRepository {
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
  }) async {
    final section = ForumSection.values.firstWhere(
      (item) => item.communityId == communityId,
      orElse: () => ForumSection.unboxing,
    );
    _store.addPost(PostDraft(
      title: title,
      body: content,
      section: section,
      isGameShare: type == 'game_share',
      isPoll: type == 'poll',
    ));
    return {'id': _store.posts.first.id, 'idempotency_key': idempotencyKey};
  }

  @override
  Future<Map<String, dynamic>> createPoll({
    required String postId,
    required String question,
    required List<String> options,
    bool allowMultiple = false,
    DateTime? endsAt,
  }) async => {'id': 'poll-$postId', 'post_id': postId, 'options': options};

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
}
