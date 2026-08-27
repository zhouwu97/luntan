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

/// 开发构建的默认 API 地址。
///
/// 真实客户端默认连接自己的 Go 服务，不再因为忘记传 Dart define 而静默
/// 展示本地演示数据。部署到其他环境时仍可通过 API_BASE_URL 覆盖；生产环境
/// 必须显式使用 HTTPS 地址。
const defaultDevelopmentApiBaseUrl = 'http://101.42.27.44';

String apiBaseUrlFromEnvironment({String? defaultBaseUrl}) {
  const configured = String.fromEnvironment('API_BASE_URL');
  const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'development');
  final effective = configured.trim().isEmpty
      ? (requiresConfiguredApi(appEnv) ? '' : (defaultBaseUrl ?? ''))
      : configured;
  return resolveApiBaseUrl(configured: effective, appEnv: appEnv);
}

bool requiresConfiguredApi(String appEnv) {
  switch (appEnv.trim().toLowerCase()) {
    case 'qa':
    case 'staging':
    case 'production':
      return true;
    default:
      return false;
  }
}

/// 解析编译期 API 地址。
///
/// QA 可以继续使用 HTTP；生产构建必须显式声明 APP_ENV=production，并且
/// 通过 HTTPS 访问 API，避免 Token、媒体和 PWA 资源落入明文链路。
String resolveApiBaseUrl({required String configured, required String appEnv}) {
  final baseUrl = configured.trim();
  if (baseUrl.isEmpty) {
    if (requiresConfiguredApi(appEnv)) {
      throw StateError('${appEnv.trim()} 环境必须配置 API_BASE_URL，禁止回退到 Mock');
    }
    // 开发和测试环境允许显式选择 Mock，避免 Android、Web、桌面端因为默认值
    // 不同而出现无法复现的真实 API / Mock 混用。
    return '';
  }
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
    throw StateError('API_BASE_URL 必须是完整的 HTTP(S) 地址');
  }
  if (appEnv.trim().toLowerCase() == 'production' &&
      uri.scheme.toLowerCase() != 'https') {
    throw StateError('生产环境 API_BASE_URL 必须使用 HTTPS');
  }
  return baseUrl;
}

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
      // Mock 首页故意按小页返回，保留真实 API 的触底分页链路，便于本地
      // 验证下滑追加、loading more 和游标去重；单元测试仍可直接使用默认
      // pageSize 覆盖完整数据集。
      feed: MockFeedRepository(store: actualStore, pageSize: 3),
      post: MockPostRepository(store: actualStore),
      comments: MockCommentRepository(store: actualStore),
      interactions: MockInteractionRepository(),
      platform: MockPlatformRepository(store: actualStore),
      appeals: MockAppealRepository(),
      bookmarks: MockBookmarkRepository(store: actualStore),
      publish: MockPublishRepository(store: actualStore),
    );
  }

  factory ForumRepositories.fromEnvironment({
    ForumStore? store,
    TokenStore? tokenStore,
    String? defaultBaseUrl,
  }) {
    final baseUrl = apiBaseUrlFromEnvironment(defaultBaseUrl: defaultBaseUrl);
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
    String? defaultBaseUrl,
  }) async {
    final baseUrl = apiBaseUrlFromEnvironment(defaultBaseUrl: defaultBaseUrl);
    if (baseUrl.trim().isEmpty) return ForumRepositories.mock(store: store);
    final actualTokenStore = tokenStore ?? await SecureTokenStore.create();
    return ForumRepositories.fromEnvironment(
      store: store,
      tokenStore: actualTokenStore,
      defaultBaseUrl: defaultBaseUrl,
    );
  }

  void close() => apiClient?.close();
}
