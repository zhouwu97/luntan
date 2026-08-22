import 'api/api_client.dart';
import 'api/api_repositories.dart';
import 'api/auth_repository.dart';
import 'api/interaction_repository.dart';
import 'api/publish_repository.dart';
import 'mock_forum_data.dart';
import 'repositories/mock_repositories.dart';
import '../domain/repositories.dart';

class ForumRepositories {
  const ForumRepositories({
    required this.community,
    required this.feed,
    required this.post,
    this.apiClient,
    this.auth,
    this.interactions,
    this.publish,
  });

  final CommunityRepository community;
  final FeedRepository feed;
  final PostRepository post;
  final ApiClient? apiClient;
  final AuthRepository? auth;
  final InteractionRepository? interactions;
  final PublishRepository? publish;

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
    final tokenStore = MemoryTokenStore();
    final authenticatedClient = ApiClient(
      baseUri: Uri.parse(baseUrl),
      tokenStore: tokenStore,
    );
    return ForumRepositories(
      community: ApiCommunityRepository(authenticatedClient),
      feed: ApiFeedRepository(authenticatedClient),
      post: ApiPostRepository(authenticatedClient),
      apiClient: authenticatedClient,
      auth: AuthRepository(client: authenticatedClient, tokenStore: tokenStore),
      interactions: ApiInteractionRepository(authenticatedClient),
      publish: ApiPublishRepository(authenticatedClient),
    );
  }

  void close() => apiClient?.close();
}
