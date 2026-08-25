import 'api/api_client.dart';
import 'api/appeal_repository.dart';
import 'api/api_repositories.dart';
import 'api/auth_repository.dart';
import 'api/bookmark_repository.dart';
import 'api/comment_repository.dart';
import 'api/interaction_repository.dart';
import 'api/platform_repository.dart';
import 'api/publish_repository.dart';
import 'api/profile_repository.dart';
import 'api/poll_repository.dart';
import 'api/ranking_repository.dart';
import 'api/store_repository.dart';
import 'api/user_repository.dart';
import 'api/secure_token_store.dart';
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
    this.comments,
    this.interactions,
    this.platform,
    this.appeals,
    this.publish,
    this.profile,
    this.poll,
    this.ranking,
    this.store,
    this.bookmarks,
    this.users,
    this.isApiMode = false,
  });

  final CommunityRepository community;
  final FeedRepository feed;
  final PostRepository post;
  final ApiClient? apiClient;
  final AuthRepository? auth;
  final CommentRepository? comments;
  final InteractionRepository? interactions;
  final PlatformRepository? platform;
  final AppealRepository? appeals;
  final PublishRepository? publish;
  final ProfileRepository? profile;
  final PollRepository? poll;
  final RankingRepository? ranking;
  final StoreRepository? store;
  final BookmarkRepository? bookmarks;
  final UserRepository? users;
  final bool isApiMode;

  factory ForumRepositories.mock({ForumStore? store}) {
    final actualStore = store ?? ForumStore.seeded();
    return ForumRepositories(
      community: MockCommunityRepository(store: actualStore),
      feed: MockFeedRepository(store: actualStore),
      post: MockPostRepository(store: actualStore),
      comments: MockCommentRepository(store: actualStore),
      interactions: MockInteractionRepository(),
      appeals: MockAppealRepository(),
      bookmarks: MockBookmarkRepository(store: actualStore),
      publish: MockPublishRepository(store: actualStore),
    );
  }

  factory ForumRepositories.fromEnvironment({
    ForumStore? store,
    TokenStore? tokenStore,
  }) {
    const baseUrl = String.fromEnvironment('API_BASE_URL');
    if (baseUrl.trim().isEmpty) return ForumRepositories.mock(store: store);
    // API 模式下未显式注入令牌存储时默认使用平台安全存储，避免进程重启后
    // 会话丢失；MemoryTokenStore 只应出现在测试注入路径。
    final actualTokenStore = tokenStore ?? SecureTokenStore();
    final authenticatedClient = ApiClient(
      baseUri: Uri.parse(baseUrl),
      tokenStore: actualTokenStore,
    );
    return ForumRepositories(
      community: ApiCommunityRepository(authenticatedClient),
      feed: ApiFeedRepository(authenticatedClient),
      post: ApiPostRepository(authenticatedClient),
      apiClient: authenticatedClient,
      auth: AuthRepository(
        client: authenticatedClient,
        tokenStore: actualTokenStore,
      ),
      comments: ApiCommentRepository(authenticatedClient),
      interactions: ApiInteractionRepository(authenticatedClient),
      bookmarks: ApiBookmarkRepository(authenticatedClient),
      platform: ApiPlatformRepository(authenticatedClient),
      appeals: AppealRepository(authenticatedClient),
      publish: ApiPublishRepository(authenticatedClient),
      profile: ProfileRepository(authenticatedClient),
      poll: PollRepository(authenticatedClient),
      ranking: RankingRepository(authenticatedClient),
      store: StoreRepository(authenticatedClient),
      users: ApiUserRepository(authenticatedClient),
      isApiMode: true,
    );
  }

  /// 创建正式运行时的仓储集合。
  ///
  /// API 模式下如果调用方没有显式提供令牌存储，默认使用平台安全存储，
  /// 避免进程重启后误退回到只存在内存中的会话。测试仍可使用
  /// [fromEnvironment] 配合 [MemoryTokenStore] 注入可控依赖。
  static Future<ForumRepositories> create({
    ForumStore? store,
    TokenStore? tokenStore,
  }) async {
    const baseUrl = String.fromEnvironment('API_BASE_URL');
    if (baseUrl.trim().isEmpty) return ForumRepositories.mock(store: store);
    final actualTokenStore = tokenStore ?? await SecureTokenStore.create();
    return ForumRepositories.fromEnvironment(
      store: store,
      tokenStore: actualTokenStore,
    );
  }

  void close() => apiClient?.close();
}
