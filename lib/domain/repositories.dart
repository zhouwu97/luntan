import 'models.dart';

abstract interface class CommunityRepository {
  Future<List<Community>> getCommunities({String? categoryId, CommunityStatus? status});

  Future<Community?> getCommunity(String id);
}

abstract interface class FeedRepository {
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20});
}

abstract interface class PostRepository {
  Future<PostDetail?> getPost(String id);
}
