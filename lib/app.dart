import 'package:flutter/material.dart';

import 'controllers/auth_controller.dart';
import 'controllers/comments_controller.dart';
import 'controllers/feed_controller.dart';
import 'controllers/interaction_controller.dart';
import 'controllers/post_detail_controller.dart';
import 'controllers/publish_controller.dart';
import 'data/api/api_client.dart';
import 'data/api/auth_repository.dart';
import 'data/mock_forum_data.dart';
import 'data/repository_provider.dart';
import 'domain/models.dart';
import 'domain/repositories.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/post_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/composer_sheet.dart';
import 'widgets/messages_sheet.dart';

class LuntanApp extends StatefulWidget {
  const LuntanApp({super.key, this.tokenStore, this.repositories});

  final TokenStore? tokenStore;
  final ForumRepositories? repositories;

  @override
  State<LuntanApp> createState() => _LuntanAppState();
}

class _LuntanAppState extends State<LuntanApp> {
  late final ForumStore store;
  late final ForumRepositories repositories;
  late final FeedController feedController;
  late final InteractionController interactionController;
  late final PublishController publishController;
  AuthController? authController;
  Future<void>? authInitialization;
  int currentTab = 0;
  bool browseWithoutAuth = false;
  int unreadCount = 0;

  bool get apiMode => repositories.isApiMode;
  AuthUser? get currentUser => authController?.user;

  @override
  void initState() {
    super.initState();
    // API 模式只创建空的 UI 状态容器；业务数据全部来自 Repository。
    const baseUrl = String.fromEnvironment('API_BASE_URL');
    store = baseUrl.trim().isEmpty ? ForumStore.seeded() : ForumStore.uiOnly();
    repositories = widget.repositories ?? ForumRepositories.fromEnvironment(store: store, tokenStore: widget.tokenStore);
    feedController = FeedController(repository: repositories.feed);
    interactionController = InteractionController(repository: repositories.interactions!);
    publishController = PublishController(repository: repositories.publish!);
    final auth = repositories.auth;
    if (auth != null) {
      authController = AuthController(repository: auth);
      authInitialization = authController!.initialize().then((_) async {
        if (authController?.status == AuthStatus.authenticated) await _refreshUnreadCount();
      });
    }
  }

  @override
  void dispose() {
    authController?.dispose();
    interactionController.dispose();
    publishController.dispose();
    feedController.dispose();
    store.dispose();
    repositories.close();
    super.dispose();
  }

  void _openLogin() {
    final auth = authController;
    if (auth == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AuthScreen(controller: auth, onBrowse: () => Navigator.of(context).pop())));
  }

  bool _requireAuth() {
    if (!apiMode || authController?.status == AuthStatus.authenticated) return true;
    _openLogin();
    return false;
  }

  void showComposer() {
    if (!_requireAuth()) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ComposerSheet(
        onCreatePost: () {
          Navigator.of(sheetContext).pop();
          _showPostEditor();
        },
        onCreatePoll: () {
          Navigator.of(sheetContext).pop();
          _showPostEditor(isPoll: true);
        },
        onCreateGameShare: () {
          Navigator.of(sheetContext).pop();
          _showPostEditor(isGameShare: true);
        },
      ),
    );
  }

  Future<void> _showPostEditor({bool isGameShare = false, bool isPoll = false}) async {
    final result = await showDialog<PostDraft>(
      context: context,
      builder: (_) => PostEditorDialog(
        isGameShare: isGameShare,
        isPoll: isPoll,
        publishController: apiMode ? publishController : null,
        enableSampleMedia: !apiMode,
      ),
    );
    if (!mounted || result == null) return;
    try {
      final type = result.isGameShare ? 'game_share' : result.isPoll ? 'poll' : 'normal';
      final response = await publishController.publish(
        communityId: result.section.communityId,
        type: type,
        title: result.title,
        content: result.body,
        mediaIds: result.mediaIds,
      );
      if (result.isPoll && response['id'] is String) {
        await publishController.createPoll(
          postId: response['id'] as String,
          question: result.title,
          options: result.pollOptions,
          allowMultiple: result.allowMultiple,
          endsAt: result.pollEndsAt,
        );
      }
      await feedController.setQuery(communityId: result.section.communityId, sort: 'latest');
      if (!mounted) return;
      setState(() => currentTab = 0);
      _showQuickFeedback('帖子已发布');
    } catch (error) {
      if (mounted) _showQuickFeedback(userFacingApiMessage(error, fallback: '发布失败，草稿内容可重新填写后重试'));
    }
  }

  void openPost(Post post, {bool focusComments = false}) {
    if (!apiMode) store.recordHistory(post);
    if (apiMode && repositories.profile != null && post.id.isNotEmpty) {
      // 浏览历史是服务端事实；失败不阻塞打开帖子，详情页仍可正常阅读。
      repositories.profile!.recordHistory(post.id).catchError((_) {});
    }
    final detailController = PostDetailController(repository: repositories.post, postId: post.id);
    final commentsController = CommentsController(repository: repositories.comments!, postId: post.id);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PostDetailScreen(
      controller: detailController,
      commentsController: commentsController,
      interactionController: interactionController,
      currentUserId: currentUser?.id ?? 'user-1',
      focusComments: focusComments,
      onToggleLike: togglePostLike,
      onToggleBookmark: toggleBookmark,
      onFeedback: _showQuickFeedback,
      onDeletePost: deletePost,
      onEditPost: editPost,
      onReport: report,
      pollRepository: repositories.poll,
    ))).then((_) {
      // 详情页返回时用其最终帖子状态做增量同步，避免无条件整页刷新。
      // 编辑/删除等结构化变更已由各自回调刷新 Feed。
      final detailPost = detailController.state.detail?.post;
      detailController.dispose();
      commentsController.dispose();
      if (apiMode && detailPost != null) {
        feedController.applyDetailResult(detailPost);
      }
    });
  }

  void openPostId(String postId) {
    openPost(Post(id: postId, authorId: '', communityId: '', title: '', content: '', createdAt: DateTime.now(), updatedAt: DateTime.now()));
  }

  Future<void> togglePostLike(Post post) async {
    if (!_requireAuth()) return;
    try {
      await interactionController.togglePostLike(post);
    } catch (error) {
      if (mounted) _showQuickFeedback(userFacingApiMessage(error));
    }
  }

  Future<void> toggleBookmark(Post post) async {
    if (!_requireAuth()) return;
    try {
      await interactionController.toggleBookmark(post);
    } catch (error) {
      if (mounted) _showQuickFeedback(userFacingApiMessage(error));
    }
  }

  Future<void> editPost(Post post, String title, String content) async {
    final repository = repositories.post;
    if (repository is! PostMutationRepository) throw const ApiException(type: ApiErrorType.unknown, message: '当前模式暂不支持编辑帖子');
    final mutationRepository = repository as PostMutationRepository;
    await mutationRepository.updatePost(
      postId: post.id,
      communityId: post.communityId,
      type: _wirePostType(post.type),
      title: title,
      content: content,
      mediaIds: post.media.map((item) => item.id).toList(),
    );
    await feedController.refresh();
  }

  Future<void> deletePost(Post post) async {
    final repository = repositories.post;
    if (repository is! PostMutationRepository) throw const ApiException(type: ApiErrorType.unknown, message: '当前模式暂不支持删除帖子');
    final mutationRepository = repository as PostMutationRepository;
    await mutationRepository.deletePost(post.id);
    await feedController.refresh();
  }

  Future<void> report(String targetType, String targetId) async {
    final platform = repositories.platform;
    if (platform == null) return;
    await platform.report(targetType: targetType, targetId: targetId, reasonCode: 'other');
  }

  String _wirePostType(PostType type) => switch (type) {
    PostType.gameShare => 'game_share',
    PostType.poll => 'poll',
    PostType.question => 'question',
    PostType.market => 'market',
    _ => 'normal',
  };

  void _showQuickFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));
  }

  void showMessages() {
    if (!_requireAuth()) return;
    if (apiMode && repositories.platform != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NotificationsScreen(repository: repositories.platform!, onOpenPostId: openPostId))).then((_) => _refreshUnreadCount());
      return;
    }
    store.markMessagesRead();
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => const MessagesSheet());
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
    interactionController.clearUserState();
    if (mounted) setState(() => currentTab = 0);
  }

  Widget _authOrMain() {
    final auth = authController;
    if (auth == null) return _mainShell();
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        if (auth.status == AuthStatus.unknown) return const _SplashScreen();
        if (auth.status == AuthStatus.authenticated || browseWithoutAuth) return _mainShell();
        return AuthScreen(controller: auth, onBrowse: () => setState(() => browseWithoutAuth = true));
      },
    );
  }

  Widget _mainShell() {
    return Scaffold(
      body: IndexedStack(
        index: currentTab == 1 ? 0 : currentTab,
        children: [
          HomeScreen(
            store: store,
            feedController: feedController,
            onOpenPost: openPost,
            onOpenPostId: openPostId,
            onOpenComments: (post) => openPost(post, focusComments: true),
            onOpenProfile: () => setState(() => currentTab = 2),
            onOpenComposer: showComposer,
            onOpenMessages: showMessages,
            onFeedback: _showQuickFeedback,
            onToggleLike: (post) => togglePostLike(post),
            onToggleBookmark: (post) => toggleBookmark(post),
            onRequireAuth: _openLogin,
            onSectionChanged: (section) => feedController.setQuery(communityId: section.communityId, sort: store.selectedSort.name),
            platform: repositories.platform,
            unread: apiMode ? unreadCount : null,
            interactionController: interactionController,
            feedRepository: repositories.isApiMode ? repositories.feed : null,
          ),
          const SizedBox.shrink(),
          ProfileScreen(
            store: store,
            currentUser: currentUser,
            currentUserId: currentUser?.id ?? 'user-1',
            isApiMode: apiMode,
            onOpenPost: openPost,
            onOpenHome: () => setState(() => currentTab = 0),
            onOpenComposer: showComposer,
            onOpenMessages: showMessages,
            onFeedback: _showQuickFeedback,
            onLogout: _logout,
            profileRepository: repositories.profile,
            storeRepository: repositories.store,
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(currentTab: currentTab, onHome: () => setState(() => currentTab = 0), onProfile: () => setState(() => currentTab = 2), onCreate: showComposer),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner: false, title: '浅蓝论坛', theme: AppTheme.light, home: _authOrMain());
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 14), Text('正在检查登录状态', style: TextStyle(color: AppTheme.textSecondary))])));
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.currentTab, required this.onHome, required this.onProfile, required this.onCreate});
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
              Expanded(child: _BottomItem(icon: Icons.home_rounded, label: '首页', active: currentTab == 0, onTap: onHome)),
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
                          borderRadius: BorderRadius.circular(AppTheme.publishRadius),
                          boxShadow: const [BoxShadow(color: Color(0x355A9EFF), blurRadius: 16, offset: Offset(0, 7))],
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: _BottomItem(icon: Icons.person_rounded, label: '我的', active: currentTab == 2, onTap: onProfile)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) { final color = active ? AppTheme.primary : AppTheme.textSecondary; return InkWell(onTap: onTap, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color, size: 24), const SizedBox(height: 4), Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500))])); }
}
