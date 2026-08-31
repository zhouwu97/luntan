import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'controllers/app_update_coordinator.dart';
import 'controllers/auth_controller.dart';
import 'controllers/comments_controller.dart';
import 'controllers/feed_controller.dart';
import 'controllers/home_personal_feed_controller.dart';
import 'controllers/interaction_controller.dart';
import 'controllers/post_detail_controller.dart';
import 'controllers/publish_controller.dart';
import 'data/api/api_client.dart';
import 'data/api/auth_repository.dart';
import 'data/api/publish_repository.dart';
import 'data/api/platform_repository.dart';
import 'data/composer_draft_storage.dart';
import 'data/mock_forum_data.dart';
import 'data/repository_provider.dart';
import 'domain/models.dart';
import 'domain/repositories.dart';
import 'screens/app_update_sheet.dart';
import 'screens/auth_screen.dart';
import 'screens/appeal_detail_screen.dart';
import 'screens/home_screen.dart';
import 'screens/home_recommendations_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/post_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/entity_screens.dart';
import 'screens/moderation_console_screen.dart';
import 'screens/moderation_notice_detail_screen.dart';
import 'screens/moderation_appeals_screen.dart';
import 'screens/my_appeals_screen.dart';
import 'screens/governance_screens.dart';
import 'screens/activity_management_screen.dart';
import 'screens/ranking_submission_review_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/composer_sheet.dart';
import 'widgets/bookmark_picker_sheet.dart';
import 'widgets/forum_rules_gate.dart';

class LuntanApp extends StatefulWidget {
  const LuntanApp({
    super.key,
    this.tokenStore,
    this.repositories,
    this.rulesGate,
  });

  final TokenStore? tokenStore;
  final ForumRepositories? repositories;

  /// 版规公告栏弹窗控制器；生产入口注入 withPreferences 实例，直接构造
  /// LuntanApp 的测试默认不展示弹窗，避免遮挡页面交互。
  final ForumRulesGateController? rulesGate;

  @override
  State<LuntanApp> createState() => _LuntanAppState();
}

class _LuntanAppState extends State<LuntanApp> with WidgetsBindingObserver {
  late final ForumStore store;
  late final ForumRepositories repositories;
  late final FeedController feedController;
  late final HomePersonalFeedController personalFeedController;
  late final InteractionController interactionController;
  late final PublishController publishController;
  AuthController? authController;
  Future<void>? authInitialization;
  int currentTab = 0;
  // 公开帖子是首页主内容，未登录时直接进入浏览态；所有互动入口都通过
  // _requireCapability 读取同一份 /me 能力集合。
  bool browseWithoutAuth = true;
  int unreadCount = 0;
  int profileRefreshToken = 0;
  late final ForumRulesGateController rulesGate;
  bool rulesGateVisible = false;
  final navigatorKey = GlobalKey<NavigatorState>();
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  BuildContext get appContext => navigatorKey.currentContext ?? context;

  bool get apiMode => repositories.isApiMode;
  AuthUser? get currentUser => authController?.user;
  bool get isAuthenticated =>
      !apiMode || authController?.status == AuthStatus.authenticated;
  bool get canModerate => currentUser?.canModerate == true;
  bool get canManageAdmins => currentUser?.canManageAdmins == true;
  bool get canManageUsers => currentUser?.canManageUsers == true;
  bool get canViewAdminLogs => currentUser?.canViewAdminLogs == true;
  bool get canBanIP => currentUser?.canBanIP == true;
  bool get canAccessGovernance =>
      canModerate ||
      canManageAdmins ||
      canManageUsers ||
      canViewAdminLogs ||
      canBanIP;

  bool get canManageBookmarks =>
      !apiMode || currentUser?.canManageBookmarks == true;

  bool get canComment => !apiMode || currentUser?.canComment == true;
  DateTime? get commentRestrictedUntil => currentUser?.commentRestrictedUntil;
  bool get commentRestricted => currentUser?.commentRestricted == true;
  bool get canReport => !apiMode || currentUser?.canReport == true;
  bool get canLike => !apiMode || currentUser?.canLike == true;
  bool get canFollow => !apiMode || currentUser?.canFollow == true;
  bool get canVote => !apiMode || currentUser?.canVote == true;
  bool get canUploadMedia => !apiMode || currentUser?.canUploadMedia == true;
  bool get canManageProfile =>
      !apiMode || currentUser?.canManageProfile == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // API 模式只创建空的 UI 状态容器；业务数据全部来自 Repository。
    // main.dart 会给正式运行时注入 API 仓储，测试/离线预览才直接构造 Mock。
    final configuredBaseUrl = apiBaseUrlFromEnvironment();
    final bootstrapStore = configuredBaseUrl.trim().isEmpty
        ? ForumStore.seeded()
        : ForumStore.uiOnly();
    repositories =
        widget.repositories ??
        ForumRepositories.fromEnvironment(
          store: bootstrapStore,
          tokenStore: widget.tokenStore,
        );
    store = repositories.isApiMode ? ForumStore.uiOnly() : bootstrapStore;
    feedController = FeedController(repository: repositories.feed);
    personalFeedController = HomePersonalFeedController(
      repository: repositories.profile,
      mockStore: store,
    );
    interactionController = InteractionController(
      repository: repositories.interactions!,
    );
    publishController = PublishController(repository: repositories.publish!);
    final auth = repositories.auth;
    if (auth != null) {
      authController = AuthController(
        repository: auth,
        profileRepository: repositories.isApiMode ? repositories.profile : null,
      );
      repositories.apiClient?.onSessionInvalidated = _handleSessionInvalidated;
      authInitialization = authController!.initialize().then((_) async {
        if (authController?.status == AuthStatus.authenticated) {
          await _refreshUnreadCount();
        }
      });
    }
    // Mock 与 API 都从同一个通知仓储读取角标；Mock 空通知列表自然返回 0。
    unawaited(_refreshUnreadCount());
    rulesGate = widget.rulesGate ?? ForumRulesGateController.disabled();
    unawaited(
      rulesGate.restore().then((_) {
        if (mounted) setState(() => rulesGateVisible = rulesGate.shouldShow);
      }),
    );
    updateCoordinator = AppUpdateCoordinator();
    unawaited(_checkStartupRequiredUpdate());
  }

  late final AppUpdateCoordinator updateCoordinator;

  /// 启动强制更新门禁：Android 上检查到服务端标记 required 的新版本时，
  /// 弹出不可关闭的更新层。检查静默失败、不阻塞启动；Web 与桌面端没有
  /// APK 安装能力，不参与门禁。
  Future<void> _checkStartupRequiredUpdate() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      await updateCoordinator.checkUpdate(manual: false);
      if (!mounted) return;
      if (updateCoordinator.isRequired) {
        await showAppUpdateSheet(
          appContext,
          force: true,
          coordinator: updateCoordinator,
        );
      }
    } catch (_) {
      // 启动检查失败不打扰用户；设置页仍可手动检查更新。
    }
  }

  Future<void> _checkForegroundUpdate() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await updateCoordinator.onAppForeground();
      if (!mounted) return;
      if (updateCoordinator.isRequired) {
        await showAppUpdateSheet(
          appContext,
          force: true,
          coordinator: updateCoordinator,
        );
      }
    } catch (_) {
      // 忽略前台检查异常
    }
  }

  void _handleSessionInvalidated() {
    authController?.invalidateSession();
    unreadCount = 0;
    feedController.reset();
    personalFeedController.reset();
    interactionController.clearUserState();
    if (!mounted) return;
    setState(() {
      // 会话失效不应把用户踢到登录墙；公开内容继续可读，互动按钮按能力
      // 重新收敛，并明确提示用户当前状态。
      browseWithoutAuth = true;
      currentTab = 0;
    });
    _showQuickFeedback('登录状态已过期，互动功能暂不可用。');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    authController?.dispose();
    interactionController.dispose();
    publishController.dispose();
    feedController.dispose();
    personalFeedController.dispose();
    store.dispose();
    repositories.close();
    updateCoordinator.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshUnreadCount());
      unawaited(_checkForegroundUpdate());
    }
  }

  void _openLogin() {
    final auth = authController;
    if (auth == null) return;
    navigatorKey.currentState!
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => AuthScreen(
              controller: auth,
              onBrowse: () => navigatorKey.currentState!.pop(),
              onGuest: _enterGuest,
            ),
          ),
        )
        .then((_) {
          // 登录/游客切换后个人中心仍可能复用原有 State；认证页关闭时
          // 主动刷新资料、积分和最近内容，避免返回页面仍停留在游客快照。
          if (!mounted) return;
          setState(() => profileRefreshToken++);
        });
  }

  Future<void> _enterGuest() async {
    final auth = authController;
    if (auth == null) return;
    final success = await auth.guest();
    if (!mounted || !success) {
      if (mounted && auth.error != null) {
        _showQuickFeedback(
          userFacingApiMessage(auth.error!, fallback: '游客模式暂时不可用'),
        );
      }
      return;
    }
    browseWithoutAuth = false;
    if (navigatorKey.currentState?.canPop() ?? false) {
      navigatorKey.currentState!.pop();
    }
    if (mounted) setState(() {});
  }

  bool _requireAuth() {
    if (!apiMode || authController?.status == AuthStatus.authenticated) {
      return true;
    }
    _openLogin();
    return false;
  }

  bool _requireCapability(String capability, String message) {
    if (!apiMode) return true;
    if (authController?.status != AuthStatus.authenticated) {
      _openLogin();
      return false;
    }
    if (currentUser?.can(capability) == true) return true;
    _showQuickFeedback(message);
    return false;
  }

  bool _requireRegisteredAccount() {
    if (!_requireAuth()) return false;
    if (!apiMode || currentUser?.canPublish == true) return true;
    _showQuickFeedback('游客可以参与评论，登录邮箱账号后即可发布帖子');
    return false;
  }

  void showComposer() {
    if (!_requireRegisteredAccount()) return;
    _openPostEditor(
      initialCommunityId: feedController.communityId ?? 'community-campus',
    );
  }

  void _openPostEditor({required String initialCommunityId}) {
    final currentUserId =
        authController?.user?.id ?? (apiMode ? 'anonymous' : 'mock-user');
    final draftStorageFuture = ComposerDraftStorage.create(
      userId: currentUserId,
    );
    final availableCommunitiesFuture = apiMode
        ? _loadPublishCommunities()
        : null;
    final canPublishActivity = authController?.user?.canModerate == true ||
        authController?.user?.capability('can_manage_activities') == true ||
        authController?.user?.capability('can_publish_activity') == true ||
        !apiMode;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => PostEditorScreen(
          initialCommunityId: initialCommunityId,
          onPublish: _publishDraft,
          userId: currentUserId,
          publishController: apiMode ? publishController : null,
          enableSampleMedia: !apiMode,
          availableCommunities: apiMode
              ? const []
              : selectHomeCommunities(store.communities),
          availableCommunitiesFuture: availableCommunitiesFuture,
          draftStorageFuture: draftStorageFuture,
          canPublishActivity: canPublishActivity,
        ),
      ),
    );
  }

  Future<List<Community>> _loadPublishCommunities() async {
    final communities = await repositories.community.getCommunities(
      status: CommunityStatus.active,
      canPublish: true,
    );

    final result = selectHomeCommunities(communities);

    if (result.isEmpty) {
      throw StateError('当前没有可发布分类');
    }

    return result;
  }

  Future<void> _publishDraft(PostDraft result) async {
    try {
      final communityId = result.communityId ?? result.section.communityId;
      await publishController.publish(
        communityId: communityId,
        type: result.isPoll ? 'poll' : result.type,
        title: result.title,
        content: result.body,
        mediaIds: result.mediaIds,
        topic: result.topic,
      );
      await feedController.setQuery(communityId: communityId, sort: 'latest');
      if (!mounted) return;
      setState(() => currentTab = 0);
      _showQuickFeedback('帖子已发布');
    } catch (error) {
      throw PublishException(
        userFacingApiMessage(error, fallback: '发布失败，草稿内容已保留，请重试'),
      );
    }
  }

  void openPostById(String postId, {String? focusCommentId, Post? seedPost}) {
    _openPostById(postId, focusCommentId: focusCommentId, seedPost: seedPost);
  }

  void _openPostById(
    String postId, {
    String? focusCommentId,
    Post? seedPost,
    bool focusComments = false,
  }) {
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) {
      _showQuickFeedback('帖子数据异常，缺少帖子 ID');
      return;
    }
    final normalizedCommentId = focusCommentId?.trim();
    final postForHistory = seedPost?.id.trim() == normalizedPostId
        ? seedPost
        : null;
    if (!apiMode && postForHistory != null) store.recordHistory(postForHistory);
    if (apiMode && repositories.profile != null) {
      // 浏览历史是服务端事实；失败不阻塞打开帖子，详情页仍可正常阅读。
      repositories.profile!.recordHistory(normalizedPostId).catchError((error) {
        if (kDebugMode) {
          debugPrint('[History] Failed to record post visit: $error');
        }
      });
    }
    final detailController = PostDetailController(
      repository: repositories.post,
      postId: normalizedPostId,
    );
    final commentsController = CommentsController(
      repository: repositories.comments!,
      postId: normalizedPostId,
    );
    navigatorKey.currentState!
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PostDetailScreen(
              controller: detailController,
              commentsController: commentsController,
              interactionController: interactionController,
              isAuthenticated:
                  !apiMode ||
                  authController?.status == AuthStatus.authenticated,
              canLike: canLike,
              canComment: canComment,
              canReport: canReport,
              canBookmark: canManageBookmarks,
              canVote: canVote,
              commentRestricted: commentRestricted,
              commentRestrictedUntil: commentRestrictedUntil,
              onRequireAuth: _openLogin,
              currentUserId: currentUser?.id,
              focusComments:
                  focusComments ||
                  (normalizedCommentId != null &&
                      normalizedCommentId.isNotEmpty),
              focusCommentId: normalizedCommentId?.isEmpty == true
                  ? null
                  : normalizedCommentId,
              onToggleLike: togglePostLike,
              onToggleBookmark: toggleBookmark,
              onFeedback: _showQuickFeedback,
              onDeletePost: deletePost,
              onEditPost: editPost,
              onReport: apiMode ? report : null,
              pollRepository: repositories.poll,
              publishRepository: repositories.publish,
              platformRepository: repositories.platform,
              canModerate: canModerate,
              onOpenUserId: openUserProfile,
            ),
          ),
        )
        .then((_) {
          // 详情页返回时用其最终帖子状态做增量同步，避免无条件整页刷新。
          final detailPost = detailController.state.detail?.post;
          detailController.dispose();
          commentsController.dispose();
          if (apiMode && detailPost != null) {
            feedController.applyDetailResult(detailPost);
            personalFeedController.applyDetailResult(detailPost);
          }
        });
  }

  void openPost(
    Post post, {
    bool focusComments = false,
    String? focusCommentId,
  }) {
    _openPostById(
      post.id,
      focusCommentId: focusCommentId,
      seedPost: post,
      focusComments: focusComments,
    );
  }

  Future<void> togglePostLike(Post post) async {
    if (!_requireCapability('can_like', '当前身份暂不能点赞，请登录邮箱账号后重试')) {
      return;
    }
    try {
      await interactionController.togglePostLike(post);
    } catch (error) {
      if (mounted) _showQuickFeedback(userFacingApiMessage(error));
    }
  }

  Future<void> toggleBookmark(Post post) async {
    if (!_requireCapability('can_bookmark', '游客模式只能浏览、评论和举报，登录邮箱账号后才能收藏')) {
      return;
    }
    try {
      final bookmarkRepository = repositories.bookmarks;
      if (bookmarkRepository == null) {
        await interactionController.toggleBookmark(post);
        return;
      }
      final active = await showModalBottomSheet<bool>(
        context: appContext,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            BookmarkPickerSheet(post: post, repository: bookmarkRepository),
      );
      if (active != null) {
        interactionController.applyBookmarkState(post, active);
      }
    } catch (error) {
      if (mounted) _showQuickFeedback(userFacingApiMessage(error));
    }
  }

  Future<void> editPost(Post post, String title, String content) async {
    final repository = repositories.post;
    if (repository is! PostMutationRepository) {
      throw const ApiException(
        type: ApiErrorType.unknown,
        message: '当前模式暂不支持编辑帖子',
      );
    }
    final mutationRepository = repository as PostMutationRepository;
    final updatedPost = await mutationRepository.updatePost(
      postId: post.id,
      communityId: post.communityId,
      type: _wirePostType(post.type),
      title: title,
      content: content,
      mediaIds: post.media.map((item) => item.id).toList(),
    );
    personalFeedController.applyDetailResult(updatedPost);
    await feedController.refresh();
  }

  Future<void> deletePost(Post post) async {
    final repository = repositories.post;
    if (repository is! PostMutationRepository) {
      throw const ApiException(
        type: ApiErrorType.unknown,
        message: '当前模式暂不支持删除帖子',
      );
    }
    final mutationRepository = repository as PostMutationRepository;
    await mutationRepository.deletePost(post.id);
    personalFeedController.removePost(post.id);
    await feedController.refresh();
  }

  Future<void> report(String targetType, String targetId) async {
    final platform = repositories.platform;
    if (platform == null) {
      throw const ApiException(
        type: ApiErrorType.unknown,
        message: '当前模式暂不支持举报',
      );
    }
    await platform.report(
      targetType: targetType,
      targetId: targetId,
      reasonCode: 'other',
    );
  }

  void openUserProfile(String userId) {
    final users = repositories.users;
    if (users == null) {
      _showQuickFeedback('当前模式暂不支持用户主页');
      return;
    }
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(
          repository: users,
          userId: userId,
          isAuthenticated: isAuthenticated,
          canFollow: canFollow,
          onRequireAuth: _openLogin,
          onFeedback: _showQuickFeedback,
          onOpenPostId: openPostById,
          onOpenRelations: openUserRelations,
        ),
      ),
    );
  }

  void openUserRelations(String userId, bool followers) {
    final users = repositories.users;
    if (users == null) {
      _showQuickFeedback('当前模式暂不支持社交列表');
      return;
    }
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => UserRelationsScreen(
          repository: users,
          userId: userId,
          followers: followers,
          isAuthenticated: isAuthenticated,
          canFollow: canFollow,
          onRequireAuth: _openLogin,
          onOpenUserId: openUserProfile,
          onFeedback: _showQuickFeedback,
        ),
      ),
    );
  }

  void openCommunity(String communityId) {
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityDetailScreen(
          repository: repositories.community,
          feedRepository: repositories.feed,
          communityId: communityId,
          isAuthenticated: isAuthenticated,
          canFollow: canFollow,
          onRequireAuth: _openLogin,
          onFeedback: _showQuickFeedback,
          onOpenPost: openPost,
          onOpenComments: (post) => openPost(post, focusComments: true),
          onToggleLike: togglePostLike,
          onToggleBookmark: toggleBookmark,
          interactionController: interactionController,
          onOpenUserId: openUserProfile,
        ),
      ),
    );
  }

  void openMyProfile() {
    if (!mounted) return;
    setState(() {
      currentTab = 2;
      profileRefreshToken++;
    });
  }

  void openModeration() {
    if (apiMode && !canModerate) {
      _showQuickFeedback('你暂时没有访问审核中心的权限');
      return;
    }
    final platform = repositories.platform;
    if (platform == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ModerationConsoleScreen(
          repository: platform,
          onFeedback: _showQuickFeedback,
          onOpenAppeals: repositories.appeals == null
              ? null
              : () => navigatorKey.currentState!.push(
                  MaterialPageRoute<void>(
                    builder: (_) => ModerationAppealsScreen(
                      repository: repositories.appeals!,
                      onFeedback: _showQuickFeedback,
                    ),
                  ),
                ),
          onOpenRecommendations: openHomeRecommendations,
        ),
      ),
    );
  }

  void openModerationAppeals() {
    final repository = repositories.appeals;
    if (repository == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ModerationAppealsScreen(
          repository: repository,
          onFeedback: _showQuickFeedback,
        ),
      ),
    );
  }

  void openGovernance() {
    if (apiMode && !canAccessGovernance) {
      _showQuickFeedback('你暂时没有访问治理中心的权限');
      return;
    }
    final platform = repositories.platform;
    if (platform == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => GovernanceCenterScreen(
          onOpenModeration: canModerate ? openModeration : null,
          onOpenAppeals: canModerate && repositories.appeals != null
              ? openModerationAppeals
              : null,
          onOpenRecommendations: canModerate ? openHomeRecommendations : null,
          onOpenActivities: canModerate ? openActivityManagement : null,
          onOpenRankingSubmissions: apiMode && canManageAdmins
              ? openRankingSubmissionReview
              : null,
          onOpenAdmins: canManageAdmins ? openAdmins : null,
          onOpenUsers: canManageUsers ? openUserManagement : null,
          onOpenRisk: canViewAdminLogs ? openRiskCenter : null,
          onOpenIPRestrictions: canBanIP ? openIPRestrictions : null,
          onOpenLogs: canViewAdminLogs ? openAdminLogs : null,
        ),
      ),
    );
  }

  void openActivityManagement() {
    if (apiMode && !canModerate) {
      _showQuickFeedback('你暂时没有管理活动的权限');
      return;
    }
    final platform = repositories.platform;
    if (platform == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ActivityManagementScreen(
          repository: platform,
          onFeedback: _showQuickFeedback,
        ),
      ),
    );
  }

  void openHomeRecommendations() {
    if (apiMode && !canModerate) {
      _showQuickFeedback('你暂时没有管理首页推荐的权限');
      return;
    }
    final platform = repositories.platform;
    if (platform == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => HomeRecommendationsScreen(
          repository: platform,
          onFeedback: _showQuickFeedback,
          onOpenPostId: openPostById,
        ),
      ),
    );
  }

  void openRankingSubmissionReview() {
    if (apiMode && !canManageAdmins) {
      _showQuickFeedback('只有超级管理员可以审核玩具投稿');
      return;
    }
    final platform = repositories.platform;
    if (platform == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => RankingSubmissionReviewScreen(
          platformRepository: platform,
          onFeedback: _showQuickFeedback,
        ),
      ),
    );
  }

  void openModerationAction(String actionId) {
    final repository = repositories.appeals;
    if (repository == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ModerationNoticeDetailScreen(
          repository: repository,
          actionId: actionId,
          publishRepository: repositories.publish,
        ),
      ),
    );
  }

  void openAppeal(String appealId) {
    final repository = repositories.appeals;
    if (repository == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AppealDetailScreen(repository: repository, appealId: appealId),
      ),
    );
  }

  void openMyAppeals() {
    final repository = repositories.appeals;
    if (repository == null) {
      _showQuickFeedback('当前模式暂不支持申诉');
      return;
    }
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => MyAppealsScreen(repository: repository),
      ),
    );
  }

  void openAccountStatus() {
    final platform = repositories.platform;
    if (platform == null) {
      _showQuickFeedback('当前模式暂不支持账号状态');
      return;
    }
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AccountStatusScreen(
          repository: platform,
          onOpenAction: openModerationAction,
        ),
      ),
    );
  }

  void openAdmins() {
    if (apiMode && !canManageAdmins) {
      _showQuickFeedback('只有超级管理员可以管理管理员权限');
      return;
    }
    final platform = repositories.platform;
    if (platform == null) {
      _showQuickFeedback('当前模式暂不支持管理员治理');
      return;
    }
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AdminListScreen(
          repository: platform,
          onOpenAdmin: openAdminDetail,
          onOpenRisk: canViewAdminLogs ? openRiskCenter : null,
          onOpenRecommendations: canModerate ? openHomeRecommendations : null,
          communityRepository: repositories.community,
        ),
      ),
    );
  }

  void openUserManagement() {
    if (apiMode && !canManageUsers) {
      _showQuickFeedback('你暂时没有访问用户管理的权限');
      return;
    }
    final platform = repositories.platform;
    if (platform == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ManagedUserListScreen(
          repository: platform,
          onOpenPostId: openPostById,
        ),
      ),
    );
  }

  void openAdminDetail(String adminId) {
    final platform = repositories.platform;
    if (platform == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AdminDetailScreen(
          repository: platform,
          adminId: adminId,
          communityRepository: repositories.community,
        ),
      ),
    );
  }

  void openRiskCenter() {
    if (apiMode && !canViewAdminLogs) {
      _showQuickFeedback('你暂时没有访问风控中心的权限');
      return;
    }
    final platform = repositories.platform;
    if (platform == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => RiskCenterScreen(
          repository: platform,
          onOpenLogs: canViewAdminLogs ? openAdminLogs : null,
          canBanIP: canBanIP,
        ),
      ),
    );
  }

  void openAdminLogs() {
    if (apiMode && !canViewAdminLogs) {
      _showQuickFeedback('你暂时没有查看操作日志的权限');
      return;
    }
    final platform = repositories.platform;
    if (platform == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AdminLogsScreen(repository: platform),
      ),
    );
  }

  void openIPRestrictions() {
    if (apiMode && !canBanIP) {
      _showQuickFeedback('只有具备 IP 封禁权限的管理员可以管理 IP 限制');
      return;
    }
    final platform = repositories.platform;
    if (platform == null) return;
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => IPRestrictionsScreen(repository: platform),
      ),
    );
  }

  String _wirePostType(PostType type) => switch (type) {
    PostType.gameShare => 'game_share',
    PostType.poll => 'poll',
    PostType.question => 'question',
    _ => 'normal',
  };

  void _showQuickFeedback(String message) {
    if (!mounted) return;
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void showMessages() {
    if (!_requireAuth()) return;
    final platform = repositories.platform;
    if (platform == null) {
      _showQuickFeedback('当前模式暂不支持通知');
      return;
    }
    navigatorKey.currentState!
        .push(
          MaterialPageRoute<void>(
            builder: (_) => NotificationsScreen(
              repository: platform,
              onOpenPostId: openPostById,
              onOpenPost: (postId, commentId) =>
                  openPostById(postId, focusCommentId: commentId),
              onOpenSystem: () => _showQuickFeedback('这是一条系统通知'),
              onOpenNotification: _openNotificationDetail,
              onOpenUserId: openUserProfile,
              onOpenCommunityId: openCommunity,
              onOpenModerationActionId: openModerationAction,
              onOpenAppealId: openAppeal,
            ),
          ),
        )
        .then((_) => _refreshUnreadCount());
  }

  void _openNotificationDetail(ForumNotification notification) {
    final platform = repositories.platform;
    if (platform == null) return;
    final data = notification.targetData;
    VoidCallback? openTarget;
    final postId = data['post_id'];
    if (postId is String && postId.isNotEmpty) {
      final commentId = data['comment_id'];
      openTarget = () {
        Navigator.of(appContext).pop();
        openPostById(
          postId,
          focusCommentId: commentId is String ? commentId : null,
        );
      };
    }
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationDetailScreen(
          repository: platform,
          notification: notification,
          onOpenTarget: openTarget,
        ),
      ),
    );
  }

  Future<void> _refreshUnreadCount() async {
    final platform = repositories.platform;
    if (platform == null) return;
    try {
      final value = await platform.unreadNotificationCount();
      if (mounted) setState(() => unreadCount = value);
    } catch (_) {
      // 未读数只是辅助信息，接口暂时不可用时不阻塞首页。
    }
  }

  Future<void> _logout() async {
    await authController?.logout();
    unreadCount = 0;
    feedController.reset();
    personalFeedController.reset();
    interactionController.clearUserState();
    if (mounted) setState(() => currentTab = 0);
  }

  Future<void> _deleteAccount() async {
    await repositories.auth?.deleteAccount();
    unreadCount = 0;
    feedController.reset();
    personalFeedController.reset();
    interactionController.clearUserState();
    if (mounted) {
      setState(() {
        browseWithoutAuth = false;
        currentTab = 0;
      });
    }
  }

  Widget _authOrMain() {
    final auth = authController;
    if (auth == null) return _mainShell();
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        // 公开内容允许游客直接浏览；登录状态检查在后台进行，不应挡住首帧。
        // 只有用户主动进入登录流程后，unknown 状态才需要展示检查中的页面。
        if (auth.status == AuthStatus.unknown && !browseWithoutAuth) {
          return const _SplashScreen();
        }
        if (auth.status == AuthStatus.authenticated || browseWithoutAuth) {
          return _mainShell();
        }
        return AuthScreen(
          controller: auth,
          onBrowse: () => setState(() => browseWithoutAuth = true),
          onGuest: _enterGuest,
        );
      },
    );
  }

  Widget _mainShell() {
    final shell = Scaffold(
      body: IndexedStack(
        index: currentTab == 1 ? 0 : currentTab,
        children: [
          HomeScreen(
            store: store,
            feedController: feedController,
            onOpenPost: openPost,
            onOpenPostId: openPostById,
            onOpenUserId: openUserProfile,
            onOpenCommunityId: openCommunity,
            onOpenComments: (post) => openPost(post, focusComments: true),
            onOpenProfile: openMyProfile,
            onOpenMessages: showMessages,
            onFeedback: _showQuickFeedback,
            onToggleLike: (post) => togglePostLike(post),
            onToggleBookmark: (post) => toggleBookmark(post),
            onRequireAuth: _openLogin,
            isAuthenticated:
                !apiMode || authController?.status == AuthStatus.authenticated,
            platform: repositories.platform,
            canModerate: canModerate,
            unread: unreadCount,
            interactionController: interactionController,
            feedRepository: repositories.isApiMode ? repositories.feed : null,
            communityRepository: repositories.isApiMode
                ? repositories.community
                : null,
            postRepository: repositories.isApiMode ? repositories.post : null,
            rankingRepository: repositories.isApiMode
                ? repositories.ranking
                : null,
            storeRepository: repositories.isApiMode ? repositories.store : null,
            publishRepository: repositories.publish,
            canManageRanking: apiMode && canManageAdmins,
            currentUser: currentUser,
            canComment: canComment,
            canLike: canLike,
            canVote: canVote,
            onRefreshCompleted: _refreshUnreadCount,
          ),
          const SizedBox.shrink(),
          ProfileScreen(
            store: store,
            currentUser: currentUser,
            currentUserId: currentUser?.id,
            isApiMode: apiMode,
            onOpenPost: openPost,
            onOpenHome: () => setState(() => currentTab = 0),
            onOpenComposer: showComposer,
            onOpenMessages: showMessages,
            onFeedback: _showQuickFeedback,
            onOpenModeration: apiMode && canModerate ? openModeration : null,
            onOpenRecommendations: apiMode && canModerate
                ? openHomeRecommendations
                : null,
            onOpenAppeals: openMyAppeals,
            onOpenAccountStatus: apiMode && isAuthenticated
                ? openAccountStatus
                : null,
            onOpenAdmins: apiMode && canManageAdmins ? openAdmins : null,
            onOpenGovernance: apiMode && canAccessGovernance
                ? openGovernance
                : null,
            onLogout: _logout,
            onDeleteAccount: apiMode ? _deleteAccount : null,
            onRequireAuth: _openLogin,
            onOpenRelations: openUserRelations,
            refreshToken: profileRefreshToken,
            profileRepository: repositories.profile,
            publishRepository: repositories.publish,
            canManageProfile: canManageProfile,
            storeRepository: repositories.store,
            bookmarkRepository: repositories.bookmarks,
            onOpenPostId: openPostById,
            onOpenPostById: openPostById,
            onProfileUpdated: () => authController?.refreshUser(),
            updateCoordinator: updateCoordinator,
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        currentTab: currentTab,
        onHome: () => setState(() => currentTab = 0),
        onProfile: openMyProfile,
        onCreate: showComposer,
      ),
    );
    if (!rulesGateVisible) return shell;
    // 版规弹窗覆盖主界面，遮罩吃掉点击，用户做出选择前无法进入论坛。
    // ForumRulesGate 自带 Positioned.fill，直接放进 Stack 即可置顶。
    return Stack(
      children: [
        Positioned.fill(child: shell),
        ForumRulesGate(onAgree: _agreeRules),
      ],
    );
  }

  Future<void> _agreeRules() async {
    await rulesGate.agree();
    if (mounted) setState(() => rulesGateVisible = false);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '圣杯酱',
    theme: AppTheme.light,
    navigatorKey: navigatorKey,
    scaffoldMessengerKey: scaffoldMessengerKey,
    home: _authOrMain(),
  );
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text('正在检查登录状态', style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.currentTab,
    required this.onHome,
    required this.onProfile,
    required this.onCreate,
  });
  final int currentTab;
  final VoidCallback onHome;
  final VoidCallback onProfile;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Expanded(
                child: _BottomItem(
                  icon: Icons.home_rounded,
                  label: '首页',
                  active: currentTab == 0,
                  onTap: onHome,
                ),
              ),
              Expanded(
                child: Center(
                  child: Semantics(
                    button: true,
                    label: '发布',
                    child: InkResponse(
                      onTap: onCreate,
                      radius: 38,
                      child: Ink(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(
                            AppTheme.publishRadius,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x355A9EFF),
                              blurRadius: 16,
                              offset: Offset(0, 7),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _BottomItem(
                  icon: Icons.person_rounded,
                  label: '我的',
                  active: currentTab == 2,
                  onTap: onProfile,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.primary : AppTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
