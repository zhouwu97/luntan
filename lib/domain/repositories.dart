import 'models.dart';

abstract interface class CommunityRepository {
  Future<List<Community>> getCommunities({
    String? categoryId,
    CommunityStatus? status,
    bool? canPublish,
  });

  Future<Community?> getCommunity(String id);
}

abstract interface class CommunityMutationRepository {
  Future<void> setFollow({required String communityId, required bool active});

  Future<void> setMembership({
    required String communityId,
    required bool active,
  });
}

abstract interface class FeedRepository {
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20});
}

/// 过滤后的 Feed 能力是可选扩展，保留 FeedRepository 旧接口以兼容离线
/// 仓储和已有测试。
abstract interface class QueryableFeedRepository {
  Future<FeedPage> getFeed({
    String? cursor,
    int limit = 20,
    String? communityId,
    String sort = 'latest',
    LatestOrder latestOrder = LatestOrder.comment,
    String? postType,
    bool? hasMedia,
    String? topic,
  });
}

abstract interface class PostRepository {
  Future<PostDetail?> getPost(String id);
}

abstract interface class PostMutationRepository {
  Future<Post> updatePost({
    required String postId,
    required String communityId,
    required String type,
    required String title,
    required String content,
    List<String> mediaIds,
  });

  Future<void> deletePost(String postId);
}
