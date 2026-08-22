import '../../domain/models.dart';
import '../../domain/repositories.dart';
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

class MockFeedRepository implements FeedRepository {
  MockFeedRepository({ForumStore? store}) : _store = store ?? ForumStore.seeded();

  final ForumStore _store;

  @override
  Future<FeedPage> getLatestFeed({String? cursor, int limit = 20}) async {
    final normalizedLimit = limit.clamp(1, 50).toInt();
    final posts = [..._store.posts]
      ..removeWhere((post) => post.publicationStatus != PublicationStatus.published || post.moderationStatus != ModerationStatus.normal)
      ..sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate == 0 ? b.id.compareTo(a.id) : byDate;
      });
    final start = int.tryParse(cursor ?? '') ?? 0;
    if (start >= posts.length) return const FeedPage(items: [], hasMore: false);
    final end = (start + normalizedLimit).clamp(0, posts.length).toInt();
    return FeedPage(items: posts.sublist(start, end), nextCursor: end < posts.length ? '$end' : null, hasMore: end < posts.length);
  }
}

class MockPostRepository implements PostRepository {
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
}
