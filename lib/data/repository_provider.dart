import 'api/api_client.dart';
import 'api/api_repositories.dart';
import 'mock_forum_data.dart';
import 'repositories/mock_repositories.dart';
import '../domain/repositories.dart';

class ForumRepositories {
  const ForumRepositories({
    required this.community,
    required this.feed,
    required this.post,
    this.apiClient,
  });

  final CommunityRepository community;
  final FeedRepository feed;
  final PostRepository post;
  final ApiClient? apiClient;

  factory ForumRepositories.mock({ForumStore? store}) {
    final actualStore = store ?? ForumStore.seeded();
    return ForumRepositories(
      community: MockCommunityRepository(store: actualStore),
      feed: MockFeedRepository(store: actualStore),
      post: MockPostRepository(store: actualStore),
    );
  }

  factory ForumRepositories.fromEnvironment({ForumStore? store}) {
    const baseUrl = String.fromEnvironment('API_BASE_URL');
    if (baseUrl.trim().isEmpty) return ForumRepositories.mock(store: store);
    final client = ApiClient(baseUri: Uri.parse(baseUrl));
    return ForumRepositories(
      community: ApiCommunityRepository(client),
      feed: ApiFeedRepository(client),
      post: ApiPostRepository(client),
      apiClient: client,
    );
  }

  void close() => apiClient?.close();
}
