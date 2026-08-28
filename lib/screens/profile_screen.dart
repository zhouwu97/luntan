import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/api/api_client.dart';
import '../data/api/auth_repository.dart';
import '../data/api/bookmark_repository.dart';
import '../data/api/profile_repository.dart';
import '../data/api/publish_repository.dart';
import '../data/api/store_repository.dart';
import '../data/api/user_repository.dart';
import '../data/mock_forum_data.dart';
import '../domain/models.dart';
import '../theme/app_theme.dart';
import 'exchange_store_screen.dart';
import 'bookmark_folders_screen.dart';
import 'entity_screens.dart';
import 'points_screen.dart';
import 'profile_list_screen.dart';
import 'settings_screen.dart';

typedef OpenPostById = void Function(String postId, {String? focusCommentId});

bool _hasUsableAvatarUrl(String? value) {
  final url = value?.trim().toLowerCase();
  return url != null &&
      (url.startsWith('https://') || url.startsWith('http://'));
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.store,
    required this.onOpenPost,
    required this.onOpenHome,
    required this.onOpenComposer,
    required this.onOpenMessages,
    required this.onFeedback,
    this.currentUser,
    required this.currentUserId,
    this.isApiMode = false,
    this.profileRepository,
    this.publishRepository,
    this.canManageProfile = true,
    this.storeRepository,
    this.bookmarkRepository,
    this.onOpenPostId,
    this.onOpenPostById,
    this.onLogout,
    this.onDeleteAccount,
    this.onRequireAuth,
    this.onOpenModeration,
    this.onOpenRecommendations,
    this.onOpenAppeals,
    this.onOpenAccountStatus,
    this.onOpenAdmins,
    this.onOpenGovernance,
    this.onOpenRelations,
    this.refreshToken = 0,
  });

  final ForumStore store;
  final ValueChanged<Post> onOpenPost;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenComposer;
  final VoidCallback onOpenMessages;
  final ValueChanged<String> onFeedback;
  final AuthUser? currentUser;
  final String? currentUserId;
  final bool isApiMode;
  final ProfileRepository? profileRepository;
  final PublishRepository? publishRepository;
  final bool canManageProfile;
  final StoreRepository? storeRepository;
  final BookmarkRepository? bookmarkRepository;
  final ValueChanged<String>? onOpenPostId;
  final OpenPostById? onOpenPostById;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onDeleteAccount;
  final VoidCallback? onRequireAuth;
  final VoidCallback? onOpenModeration;
  final VoidCallback? onOpenRecommendations;
  final VoidCallback? onOpenAppeals;
  final VoidCallback? onOpenAccountStatus;
  final VoidCallback? onOpenAdmins;
  final VoidCallback? onOpenGovernance;
  final void Function(String userId, bool followers)? onOpenRelations;
  final int refreshToken;

  void _openHomepage(BuildContext context) {
    // /me/profile 和 /me/posts 都要求 Bearer 会话；退出登录或会话失效后，
    // 仍保留 API 模式时不能拿匿名请求去渲染个人中心，否则会稳定得到 401
    // 并把游客页面错误地展示成“个人资料加载失败”。
    if (isApiMode && profileRepository != null && currentUser != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen(
            repository: ApiUserRepository(profileRepository!.client),
            userId: currentUser?.id ?? '',
            isAuthenticated:
                currentUser != null && currentUser!.accountType != 'guest',
            canFollow: false,
            onRequireAuth: onRequireAuth ?? () {},
            onFeedback: onFeedback,
            onOpenPostId: onOpenPostId ?? (_) {},
            onOpenPostById: onOpenPostById,
            onOpenRelations: onOpenRelations,
            profileRepository: profileRepository,
            publishRepository: publishRepository,
            storeRepository: storeRepository,
            isSelf: true,
          ),
        ),
      );
    } else {
      final postsCount = store.posts
          .where((p) => p.authorId == (currentUserId ?? ''))
          .length;
      final mockSummary = ProfileSummary(
        id: currentUserId ?? '',
        username: currentUser?.username ?? 'guest_user',
        nickname: currentUser?.nickname.isNotEmpty == true
            ? currentUser!.nickname
            : '游客',
        level: currentUser?.accountType == 'guest'
            ? 0
            : (currentUser?.level ?? 1),
        growth: currentUser?.growth,
        experience: currentUser?.experience ?? 0,
        trustLevel: 'new',
        signature: '还没有个性签名，点进主页完善资料',
        postCount: postsCount,
        commentCount: 0,
        likeReceivedCount: 0,
        followerCount: 0,
        followingCount: 0,
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfileScreen(
            repository: MockUserRepository(postCount: postsCount),
            userId: mockSummary.id,
            profileSummary: mockSummary,
            isAuthenticated: currentUser?.accountType != 'guest',
            canFollow: false,
            onRequireAuth: onRequireAuth ?? () {},
            onFeedback: onFeedback,
            onOpenPostId: onOpenPostId ?? (_) {},
            onOpenPostById: onOpenPostById,
            onOpenRelations: onOpenRelations,
            isSelf: true,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // /me/profile 和 /me/posts 都要求 Bearer 会话；退出登录或会话失效后，
    // 仍保留 API 模式时不能拿匿名请求去渲染个人中心，否则会稳定得到 401
    // 并把游客页面错误地展示成“个人资料加载失败”。
    if (isApiMode && profileRepository != null && currentUser != null) {
      final isGuest =
          currentUser == null || currentUser!.accountType == 'guest';
      return _ApiProfileScreen(
        repository: profileRepository!,
        currentUser: currentUser,
        onOpenPost: onOpenPost,
        onOpenHome: onOpenHome,
        onOpenComposer: onOpenComposer,
        onOpenMessages: onOpenMessages,
        onFeedback: onFeedback,
        onLogout: onLogout,
        onDeleteAccount: onDeleteAccount,
        storeRepository: storeRepository,
        bookmarkRepository: bookmarkRepository,
        publishRepository: publishRepository,
        canManageProfile: canManageProfile,
        onOpenPostId: onOpenPostId,
        onOpenPostById: onOpenPostById,
        onOpenModeration: onOpenModeration,
        onOpenRecommendations: onOpenRecommendations,
        onOpenAppeals: onOpenAppeals,
        onOpenAccountStatus: onOpenAccountStatus,
        onOpenAdmins: onOpenAdmins,
        onOpenGovernance: onOpenGovernance,
        onOpenRelations: onOpenRelations,
        isGuest: isGuest,
        accountSubtitle: isGuest ? '游客模式' : (currentUser?.email ?? '邮箱账号已登录'),
        onRequireAuth: onRequireAuth,
        refreshToken: refreshToken,
      );
    }
    final isGuest = currentUser == null || currentUser?.accountType == 'guest';
    final userPosts = store.posts
        .where((p) => p.authorId == (currentUserId ?? ''))
        .toList();
    final effectiveLevel = isGuest ? 0 : (currentUser?.level ?? 1);
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileTopbar(
                  onMessages: onOpenMessages,
                  onSettings: () => _showSettings(context),
                ),
                const SizedBox(height: 14),
                _ProfileCard(
                  nickname: currentUser?.nickname.isNotEmpty == true
                      ? currentUser!.nickname
                      : '游客',
                  username: currentUser?.username ?? 'guest_user',
                  level: effectiveLevel,
                  trustLevel: 'new',
                  signature: '还没有个性签名，点进主页完善资料',
                  avatarUrl: null,
                  postCount: userPosts.length,
                  commentCount: 0,
                  followerCount: 0,
                  followingCount: 0,
                  isGuest: isGuest,
                  experience: currentUser?.experience ?? 0,
                  onRequireAuth: onRequireAuth,
                  onTapEntry: () => _openHomepage(context),
                  onTapStat: (label) => _showList(context, label),
                ),
                if (!isApiMode) ...[
                  const SizedBox(height: 12),
                  _PointsBalanceCard(
                    balance: store.points,
                    level: effectiveLevel,
                    growth: currentUser?.growth,
                    experience: currentUser?.experience ?? 0,
                    onOpenPoints: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PointsCenterScreen(store: store),
                      ),
                    ),
                    onOpenStore: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExchangeStoreScreen(store: store),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const _SectionHeader(title: '常用功能'),
                const SizedBox(height: 10),
                _ToolsGrid(
                  onBookmarks: () => _openBookmarks(context),
                  onLikes: () => _showList(context, '我的点赞'),
                  onHistory: () => _showHistory(context),
                  onAppeals: onOpenAppeals ?? () => onFeedback('当前模式暂不支持申诉'),
                ),
                // API 未登录状态没有权威的积分余额，禁止展示本地模拟积分入口。
                if (!isApiMode) ...[
                  const SizedBox(height: 18),
                  _ExchangePreview(
                    store: store,
                    onOpenStore: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExchangeStoreScreen(store: store),
                      ),
                    ),
                    onRedeem: (product) => _redeem(context, product),
                  ),
                ],
                const SizedBox(height: 20),
                _SectionHeader(
                  title: '最近发布',
                  actionText: userPosts.isNotEmpty ? '查看全部' : null,
                  onAction: userPosts.isNotEmpty
                      ? () => _showList(context, '我的发布')
                      : null,
                ),
                const SizedBox(height: 10),
                _RecentPosts(
                  store: store,
                  currentUserId: currentUserId,
                  isGuest: isGuest,
                  onOpenPost: onOpenPost,
                  onOpenHome: onOpenHome,
                  onOpenComposer: onOpenComposer,
                  onRequireAuth: onRequireAuth,
                ),
                const SizedBox(height: 22),
                Text(
                  '杯友酱 · 把真实的玩具体验留在这里',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: .65),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsCenterScreen(
          isGuest: currentUser == null || currentUser?.accountType == 'guest',
          accountSubtitle:
              currentUser?.email ?? (isApiMode ? '未登录 · 游客体验' : null),
          onRequireAuth: onRequireAuth,
          onOpenMessages: onOpenMessages,
          onFeedback: onFeedback,
          onOpenGovernance: onOpenGovernance,
          onOpenAppeals: onOpenAppeals,
          onOpenAccountStatus: onOpenAccountStatus,
          onClearHistory: () async => store.clearHistory(),
          onLogout: onLogout,
          onDeleteAccount: onDeleteAccount,
        ),
      ),
    );
  }

  void _showList(BuildContext context, String label) {
    // API 模式: 使用 ProfileRepository 加载数据
    if (isApiMode && profileRepository != null) {
      _showApiList(context, label);
      return;
    }

    // Mock 模式: 使用 ForumStore
    final userId = currentUserId ?? 'user-1';
    final posts = switch (label) {
      '我的收藏' => store.bookmarkedPosts,
      '我的点赞' => store.likedPosts,
      '我的发布' || '我的发帖' =>
        store.posts.where((post) => post.authorId == userId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      '我的评论' || '我的回帖' =>
        store.posts
            .where((post) => post.authorId == userId)
            .where((post) => store.commentsFor(post).isNotEmpty)
            .toList()
          ..sort((a, b) {
            final aComments = store.commentsFor(a);
            final bComments = store.commentsFor(b);
            final byTime = bComments.last.createdAt.compareTo(
              aComments.last.createdAt,
            );
            return byTime == 0 ? b.id.compareTo(a.id) : byTime;
          }),
      _ => <Post>[],
    };
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 460,
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: posts.isEmpty
                    ? Center(
                        child: Text(
                          '$label暂时为空，去首页逛逛吧',
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView(
                        children: [
                          ...posts.map(
                            (post) => ListTile(
                              leading: const Icon(
                                Icons.article_outlined,
                                color: AppTheme.primary,
                              ),
                              title: Text(
                                post.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${post.community?.name ?? post.section.label} · ${post.comments} 回复',
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                final openById = onOpenPostById;
                                if (openById != null) {
                                  openById(post.id);
                                } else {
                                  onOpenPost(post);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showApiList(BuildContext context, String label) {
    final repository = profileRepository;
    if (repository == null) {
      _showFallbackMessage(context, label, '功能暂不可用');
      return;
    }

    final kind = switch (label) {
      '我的发布' || '我的发帖' => 'posts',
      '我的评论' || '我的回帖' => 'comments',
      _ => null,
    };

    if (kind == null) {
      _showFallbackMessage(context, label, '$label暂未接入');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileListScreen(
          label: label,
          kind: kind,
          repository: repository,
          onOpenPostId: onOpenPostById ?? (id, {focusCommentId}) {},
        ),
      ),
    );
  }

  void _showFallbackMessage(BuildContext context, String label, String message) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 200,
          child: Center(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  void _openBookmarks(BuildContext context) {
    final repository = bookmarkRepository;
    final onOpenPostId = this.onOpenPostId;
    if (repository == null || onOpenPostId == null) {
      _showList(context, '我的收藏');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookmarkFoldersScreen(
          repository: repository,
          onOpenPostId: onOpenPostId,
        ),
      ),
    );
  }

  void _showHistory(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '浏览历史',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: store.history.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有浏览记录',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: store.history.length,
                        itemBuilder: (_, index) => ListTile(
                          title: Text(
                            store.history[index].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(store.history[index].section.label),
                          onTap: () {
                            Navigator.pop(context);
                            onOpenPost(store.history[index]);
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _redeem(BuildContext context, StoreProduct product) {
    final success = store.redeem(product);
    onFeedback(success ? '已兑换${product.name}，请留意领取通知' : '积分不足，再攒一攒就可以兑换啦');
  }
}

/// 正式模式的个人中心只依赖服务器返回的聚合数据和列表，不读取 ForumStore。
class _ApiProfileScreen extends StatefulWidget {
  const _ApiProfileScreen({
    required this.repository,
    this.currentUser,
    required this.onOpenPost,
    required this.onOpenHome,
    this.onOpenComposer,
    required this.onOpenMessages,
    required this.onFeedback,
    this.storeRepository,
    this.bookmarkRepository,
    this.onOpenPostId,
    this.onOpenPostById,
    this.onLogout,
    this.onDeleteAccount,
    this.onOpenModeration,
    this.onOpenRecommendations,
    this.onOpenAppeals,
    this.onOpenAccountStatus,
    this.onOpenAdmins,
    this.onOpenGovernance,
    this.onOpenRelations,
    this.isGuest = false,
    this.accountSubtitle,
    this.onRequireAuth,
    this.publishRepository,
    this.canManageProfile = true,
    required this.refreshToken,
  });

  final ProfileRepository repository;
  final AuthUser? currentUser;
  final ValueChanged<Post> onOpenPost;
  final VoidCallback onOpenHome;
  final VoidCallback? onOpenComposer;
  final VoidCallback onOpenMessages;
  final ValueChanged<String> onFeedback;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onDeleteAccount;
  final VoidCallback? onOpenModeration;
  final VoidCallback? onOpenRecommendations;
  final VoidCallback? onOpenAppeals;
  final VoidCallback? onOpenAccountStatus;
  final VoidCallback? onOpenAdmins;
  final VoidCallback? onOpenGovernance;
  final void Function(String userId, bool followers)? onOpenRelations;
  final bool isGuest;
  final String? accountSubtitle;
  final VoidCallback? onRequireAuth;
  final int refreshToken;
  final StoreRepository? storeRepository;
  final BookmarkRepository? bookmarkRepository;
  final ValueChanged<String>? onOpenPostId;
  final OpenPostById? onOpenPostById;
  final PublishRepository? publishRepository;
  final bool canManageProfile;

  @override
  State<_ApiProfileScreen> createState() => _ApiProfileScreenState();
}

class _ApiProfileScreenState extends State<_ApiProfileScreen> {
  late Future<ProfileSummary> profileFuture;
  late Future<PointsOverview>? pointsFuture;
  late Future<ProfileListPage> recentPostsFuture;

  @override
  void initState() {
    super.initState();
    profileFuture = widget.repository.getProfile();
    pointsFuture = widget.storeRepository?.overview();
    recentPostsFuture = widget.repository.list(
      'posts',
      limit: 3,
      includeDetails: true,
    );
  }

  @override
  void didUpdateWidget(covariant _ApiProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final profile = widget.repository.getProfile();
    final points = widget.storeRepository?.overview();
    final recent = widget.repository.list(
      'posts',
      limit: 3,
      includeDetails: true,
    );
    setState(() {
      profileFuture = profile;
      pointsFuture = points;
      recentPostsFuture = recent;
    });
    try {
      await profile;
    } catch (_) {
      // FutureBuilder 保留错误态；下拉刷新本身不再向上抛异常。
    }
  }

  void retry() {
    _refresh();
  }

  void _openHomepage(ProfileSummary profile) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => UserProfileScreen(
              repository: ApiUserRepository(widget.repository.client),
              userId: profile.id,
              profileSummary: profile,
              isAuthenticated: !widget.isGuest,
              canFollow: false,
              onRequireAuth: widget.onRequireAuth ?? () {},
              onFeedback: widget.onFeedback,
              onOpenPostId: widget.onOpenPostId ?? (_) {},
              onOpenPostById: widget.onOpenPostById,
              onOpenRelations: widget.onOpenRelations,
              profileRepository: widget.repository,
              publishRepository: widget.publishRepository,
              storeRepository: widget.storeRepository,
              isSelf: true,
            ),
          ),
        )
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ProfileSummary>(
    future: profileFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '个人资料加载失败',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                TextButton(onPressed: retry, child: const Text('重试')),
              ],
            ),
          ),
        );
      }
      return _content(snapshot.data!);
    },
  );

  Widget _content(ProfileSummary profile) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _ProfileTopbar(
              onMessages: widget.onOpenMessages,
              onSettings: () => _showSettings(context),
            ),
            const SizedBox(height: 14),
            _ProfileCard(
              nickname: profile.nickname.isNotEmpty ? profile.nickname : '游客',
              username: profile.username,
              level: profile.level,
              trustLevel: profile.trustLevel,
              signature: profile.signature.isNotEmpty
                  ? profile.signature
                  : '还没有个性签名，点进主页完善资料',
              avatarUrl: profile.avatarUrl,
              postCount: profile.postCount,
              commentCount: profile.commentCount,
              followerCount: profile.followerCount,
              followingCount: profile.followingCount,
              isGuest: widget.isGuest,
              experience: profile.experience,
              onRequireAuth: widget.onRequireAuth,
              onTapEntry: () => _openHomepage(profile),
              onTapStat: (label) {
                if (label == '粉丝') {
                  if (widget.onOpenRelations != null) {
                    widget.onOpenRelations!(profile.id, true);
                  }
                } else if (label == '关注') {
                  if (widget.onOpenRelations != null) {
                    widget.onOpenRelations!(profile.id, false);
                  }
                } else {
                  _showList(label);
                }
              },
            ),
            if (widget.storeRepository != null) ...[
              const SizedBox(height: 12),
              FutureBuilder<PointsOverview>(
                future: pointsFuture,
                builder: (context, snapshot) => _PointsBalanceCard(
                  balance: snapshot.data?.balance,
                  level: profile.level,
                  growth: profile.growth,
                  experience: profile.experience,
                  onOpenPoints: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PointsCenterScreen(
                        apiRepository: widget.storeRepository!,
                      ),
                    ),
                  ),
                  onOpenStore: () => Navigator.of(context)
                      .push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExchangeStoreScreen(
                            apiRepository: widget.storeRepository!,
                          ),
                        ),
                      )
                      .then((_) {
                        if (mounted) {
                          setState(
                            () => pointsFuture = widget.storeRepository!
                                .overview(),
                          );
                        }
                      }),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const _SectionHeader(title: '常用功能'),
            const SizedBox(height: 10),
            _ToolsGrid(
              onBookmarks: () => _openBookmarks(),
              onLikes: () => _openLikes(),
              onHistory: () => _showList('浏览历史'),
              onAppeals:
                  widget.onOpenAppeals ?? () => widget.onFeedback('当前模式暂不支持申诉'),
            ),
            const SizedBox(height: 20),
            _SectionHeader(
              title: '最近发布',
              actionText: profile.postCount > 0 ? '查看全部' : null,
              onAction: profile.postCount > 0 ? () => _showList('我的发布') : null,
            ),
            const SizedBox(height: 10),
            _RecentPostsApi(
              recentPostsFuture: recentPostsFuture,
              isGuest: widget.isGuest,
              onOpenPostById: widget.onOpenPostById,
              onOpenPost: widget.onOpenPost,
              onOpenHome: widget.onOpenHome,
              onOpenComposer: widget.onOpenComposer,
              onRequireAuth: widget.onRequireAuth,
            ),
            const SizedBox(height: 22),
            Text(
              '杯友酱 · 把真实的玩具体验留在这里',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: .65),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _openLikes() {
    if (widget.isGuest || widget.currentUser?.canLike == false) {
      if (widget.onRequireAuth != null) {
        widget.onRequireAuth!();
      } else {
        widget.onFeedback('登录或注册邮箱账号后即可查看点赞');
      }
      return;
    }
    _showList('我的点赞');
  }

  Future<void> _showList(String label) async {
    final kind = switch (label) {
      '我的发布' || '我的发帖' => 'posts',
      '我的评论' || '我的回帖' => 'comments',
      '我的收藏' => 'bookmarks',
      '我的点赞' => 'likes',
      '浏览历史' => 'history',
      _ => 'posts',
    };
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ProfileListSheet(
        label: label,
        kind: kind,
        repository: widget.repository,
        onOpenPost: widget.onOpenPost,
        onOpenPostById: widget.onOpenPostById,
      ),
    );
  }

  void _openBookmarks() {
    if (widget.isGuest || widget.currentUser?.canManageBookmarks == false) {
      if (widget.onRequireAuth != null) {
        widget.onRequireAuth!();
      } else {
        widget.onFeedback('登录或注册邮箱账号后即可查看收藏');
      }
      return;
    }
    final repository = widget.bookmarkRepository;
    final onOpenPostId = widget.onOpenPostId;
    if (repository == null || onOpenPostId == null) {
      _showList('我的收藏');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookmarkFoldersScreen(
          repository: repository,
          onOpenPostId: onOpenPostId,
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsCenterScreen(
          isGuest: widget.isGuest,
          accountSubtitle: widget.accountSubtitle,
          onRequireAuth: widget.onRequireAuth,
          onOpenMessages: widget.onOpenMessages,
          onFeedback: widget.onFeedback,
          onOpenGovernance: widget.onOpenGovernance,
          onOpenAppeals: widget.onOpenAppeals,
          onOpenAccountStatus: widget.onOpenAccountStatus,
          onClearHistory: () => widget.repository.clearHistory(),
          onLogout: widget.onLogout,
          onDeleteAccount: widget.onDeleteAccount,
        ),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.repository,
    this.publishRepository,
  });

  final ProfileSummary profile;
  final ProfileRepository repository;
  final PublishRepository? publishRepository;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController nicknameController;
  late final TextEditingController signatureController;
  XFile? avatarFile;
  Uint8List? avatarBytes;
  bool saving = false;
  String? errorText;

  @override
  void initState() {
    super.initState();
    nicknameController = TextEditingController(text: widget.profile.nickname);
    signatureController = TextEditingController(text: widget.profile.signature);
  }

  @override
  void dispose() {
    nicknameController.dispose();
    signatureController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (saving) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (!mounted || file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      setState(() => errorText = '头像不能超过 10 MB');
      return;
    }
    setState(() {
      avatarFile = file;
      avatarBytes = bytes;
      errorText = null;
    });
  }

  Future<String?> _uploadAvatar() async {
    final publisher = widget.publishRepository;
    final file = avatarFile;
    final bytes = avatarBytes;
    if (publisher == null || file == null || bytes == null) {
      return widget.profile.avatarMediaId;
    }
    final lower = file.name.toLowerCase();
    final mimeType = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
    final digest = sha256.convert(bytes).toString();
    final ticket = await publisher.requestMediaUpload(
      fileName: file.name,
      mimeType: mimeType,
      size: bytes.length,
      sha256: digest,
    );
    if (DateTime.now().isAfter(ticket.expiresAt)) {
      throw const PublishException('头像上传凭证已过期，请重新选择');
    }
    await publisher.uploadMedia(
      ticket: ticket,
      bytes: bytes,
      size: bytes.length,
      sha256: digest,
    );
    return ticket.mediaId;
  }

  Future<void> _save() async {
    final nickname = nicknameController.text.trim();
    final signature = signatureController.text.trim();
    if (nickname.isEmpty) {
      setState(() => errorText = '昵称不能为空');
      return;
    }
    if (nickname.length > 64 || signature.length > 200) {
      setState(() => errorText = '昵称最多 64 字，签名最多 200 字');
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      final avatarMediaId = await _uploadAvatar();
      await widget.repository.updateProfile(
        nickname: nickname,
        signature: signature,
        avatarMediaId: avatarMediaId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          saving = false;
          errorText = userFacingApiMessage(error, fallback: '资料保存失败，请重试');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('编辑个人资料'),
      actions: [
        TextButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? '保存中…' : '保存'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: GestureDetector(
            onTap: _pickAvatar,
            child: CircleAvatar(
              radius: 42,
              backgroundColor: AppTheme.surfaceBlue,
              backgroundImage: avatarBytes == null
                  ? (_hasUsableAvatarUrl(widget.profile.avatarUrl)
                        ? NetworkImage(widget.profile.avatarUrl!)
                        : null)
                  : MemoryImage(avatarBytes!),
              child:
                  avatarBytes == null &&
                      !_hasUsableAvatarUrl(widget.profile.avatarUrl)
                  ? const Icon(Icons.camera_alt_outlined, size: 30)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            '点击更换头像',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: nicknameController,
          enabled: !saving,
          maxLength: 64,
          decoration: const InputDecoration(labelText: '昵称'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: signatureController,
          enabled: !saving,
          maxLength: 200,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '个性签名',
            hintText: '介绍一下现在的你…',
          ),
        ),
        if (errorText != null)
          Text(errorText!, style: const TextStyle(color: AppTheme.pink)),
      ],
    ),
  );
}

/// 个人中心列表 sheet：所有入口都展示帖子，区别只在服务端排序字段。
class _ProfileListSheet extends StatefulWidget {
  const _ProfileListSheet({
    required this.label,
    required this.kind,
    required this.repository,
    required this.onOpenPost,
    this.onOpenPostById,
  });

  final String label;
  final String kind;
  final ProfileRepository repository;
  final ValueChanged<Post> onOpenPost;
  final OpenPostById? onOpenPostById;

  @override
  State<_ProfileListSheet> createState() => _ProfileListSheetState();
}

class _ProfileListSheetState extends State<_ProfileListSheet> {
  final List<ProfilePostItem> items = [];
  final ScrollController scrollController = ScrollController();
  String? nextCursor;
  bool hasMore = true;
  bool loading = false;
  bool loadingMore = false;
  String? errorMessage;
  String? loadMoreError;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_maybeLoadMore);
    _load();
  }

  @override
  void dispose() {
    scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (scrollController.position.extentAfter < 220) _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final page = await widget.repository.list(widget.kind);
      if (!mounted) return;
      setState(() {
        items
          ..clear()
          ..addAll(page.items);
        nextCursor = page.nextCursor;
        hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted) setState(() => errorMessage = '列表加载失败，请重试');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (loading || loadingMore || !hasMore || nextCursor == null) return;
    setState(() => loadingMore = true);
    try {
      final page = await widget.repository.list(
        widget.kind,
        cursor: nextCursor,
      );
      if (!mounted) return;
      setState(() {
        items.addAll(page.items);
        nextCursor = page.nextCursor;
        hasMore = page.hasMore;
        loadMoreError = null;
      });
    } catch (_) {
      if (mounted) setState(() => loadMoreError = '加载失败 · 点击重试');
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('清空浏览历史？'),
            content: const Text('清空后将无法恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清空'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await widget.repository.clearHistory();
      if (mounted) _load();
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              errorMessage = userFacingApiMessage(error, fallback: '清空失败，请重试'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHistory = widget.kind == 'history';
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (isHistory && items.isNotEmpty)
                    TextButton(
                      onPressed: _clearHistory,
                      child: const Text('清空'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.border),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  bool get _isHistory => widget.kind == 'history';

  Widget _body() {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              errorMessage!,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          '${widget.label}暂时为空，去首页逛逛吧',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
      itemCount: items.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == items.length) {
          return loadingMore
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : loadMoreError != null
              ? TextButton(onPressed: _loadMore, child: Text(loadMoreError!))
              : const SizedBox(height: 6);
        }
        final item = items[index];
        final post = item;
        final isCommentList = widget.kind == 'comments';
        final activityAt = post.activityAt ?? post.publishedAt;
        if (isCommentList) {
          return InkWell(
            onTap: () {
              Navigator.pop(context);
              if (widget.onOpenPostById != null) {
                widget.onOpenPostById!(post.id, focusCommentId: post.commentId);
              } else {
                widget.onOpenPost(_postFromItem(post));
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '“${post.contentPreview}”',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8FA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.article_outlined,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '回复于《${post.title}》',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${post.communityName} · ${relativeTimeLabel(activityAt)}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF8DA0B2),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final title = post.title;
        final subtitle =
            '${post.communityName} · ${post.commentCount} 回复 · '
            '发布于${relativeTimeLabel(post.publishedAt)}';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _isHistory ? Icons.history_rounded : Icons.article_outlined,
            color: AppTheme.primary,
          ),
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            Navigator.pop(context);
            final onOpenPostById = widget.onOpenPostById;
            if (onOpenPostById != null) {
              onOpenPostById(post.id);
            } else {
              widget.onOpenPost(_postFromItem(post));
            }
          },
        );
      },
    );
  }

  Post _postFromItem(ProfilePostItem item) => Post(
    id: item.id,
    authorId: item.authorId,
    communityId: item.communityId,
    title: item.title,
    content: item.contentPreview,
    commentCount: item.commentCount,
    likeCount: item.likeCount,
    bookmarkCount: item.bookmarkCount,
    createdAt: item.publishedAt,
    updatedAt: item.publishedAt,
    publishedAt: item.publishedAt,
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.nickname,
    required this.username,
    required this.level,
    required this.trustLevel,
    required this.signature,
    this.avatarUrl,
    required this.postCount,
    required this.commentCount,
    required this.followerCount,
    required this.followingCount,
    this.isGuest = false,
    this.experience = 0,
    this.onRequireAuth,
    required this.onTapEntry,
    required this.onTapStat,
  });

  final String nickname;
  final String username;
  final int level;
  final String trustLevel;
  final String signature;
  final String? avatarUrl;
  final int postCount;
  final int commentCount;
  final int followerCount;
  final int followingCount;
  final bool isGuest;
  final int experience;
  final VoidCallback? onRequireAuth;
  final VoidCallback onTapEntry;
  final ValueChanged<String> onTapStat;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.white, Color(0xFFF2F8FF)],
          stops: [0.0, 0.62, 1.0],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xEBDFE8F2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F274969),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // 点击进入个人主页的头部行
          InkWell(
            onTap: onTapEntry,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(22),
              bottom: Radius.circular(isGuest ? 0 : 22),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEEF7FF), Color(0xFFF6FBFF)],
                      ),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    child: ClipOval(
                      child: _hasUsableAvatarUrl(avatarUrl)
                          ? Image.network(avatarUrl!, fit: BoxFit.cover)
                          : Center(
                              child: Text(
                                nickname.isEmpty
                                    ? '游'
                                    : nickname.characters.first,
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '@$username · Lv.$level · 信任 $trustLevel',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF71869B),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          signature.isNotEmpty
                              ? signature
                              : (isGuest ? '游客账号' : '还没有个性签名，点进主页完善资料'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF93A3B2),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '个人主页',
                        style: TextStyle(
                          color: Color(0xFF377DD3),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF377DD3),
                        size: 16,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEDF2F7)),
          // 4 项统计指标行
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Row(
              children: [
                _StatButton(
                  count: postCount,
                  label: '我的发布',
                  onTap: () => onTapStat('我的发布'),
                ),
                _StatButton(
                  count: commentCount,
                  label: '我的评论',
                  onTap: () => onTapStat('我的评论'),
                ),
                _StatButton(
                  count: followerCount,
                  label: '粉丝',
                  onTap: () => onTapStat('粉丝'),
                ),
                _StatButton(
                  count: followingCount,
                  label: '关注',
                  onTap: () => onTapStat('关注'),
                ),
              ],
            ),
          ),
          if (isGuest) ...[
            const Divider(height: 1, color: Color(0xFFEDF2F7)),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF7FAFD),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(22),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '游客模式 · 当前累计 $experience EXP',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '注册邮箱账号后保留当前经验与评论，并解锁等级和发布',
                          style: TextStyle(
                            color: Color(0xFF71869B),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: onRequireAuth,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '登录 / 注册',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatButton extends StatelessWidget {
  const _StatButton({
    required this.count,
    required this.label,
    required this.onTap,
  });

  final int count;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF71869B), fontSize: 10.5),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PointsBalanceCard extends StatelessWidget {
  const _PointsBalanceCard({
    required this.balance,
    required this.level,
    this.growth,
    this.experience = 0,
    required this.onOpenPoints,
    required this.onOpenStore,
  });

  final int? balance;
  final int level;
  final GrowthState? growth;
  final int experience;
  final VoidCallback onOpenPoints;
  final VoidCallback onOpenStore;

  @override
  Widget build(BuildContext context) {
    final expInLevel = growth?.experienceInLevel ?? 0;
    final expReq = growth?.experienceRequiredInLevel ?? 1000;
    final isLocked = level == 0 || growth?.levelLocked == true;
    final factor = expReq > 0 ? (expInLevel / expReq).clamp(0.05, 1.0) : 0.18;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEEF7FF), Color(0xFFE8F4FF), Color(0xFFF8FBFF)],
          stops: [0.0, 0.58, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(0xFFD7E8FB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D5A9EFF),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 13),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x143F709D),
                      blurRadius: 9,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.monetization_on_rounded,
                  color: AppTheme.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '社区积分',
                      style: TextStyle(color: Color(0xFF7690A8), fontSize: 10),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      balance == null ? '加载中…' : '$balance 积分',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onOpenPoints,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF346DA8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('明细', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: onOpenStore,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF346DA8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('兑换', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 等级经验进度行
          if (isLocked)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2EDF8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Lv.0',
                    style: TextStyle(
                      color: Color(0xFF537494),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '累计经验 $experience EXP · 🔒 注册后解锁等级',
                    style: const TextStyle(
                      color: Color(0xFF6D84A0),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Text(
                  'Lv.$level',
                  style: const TextStyle(
                    color: Color(0xFF6D84A0),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      height: 5,
                      color: const Color(0x2E739CC2),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: factor,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppTheme.primary, AppTheme.sky],
                            ),
                            borderRadius: BorderRadius.all(Radius.circular(99)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  '$expInLevel / $expReq EXP',
                  style: const TextStyle(
                    color: Color(0xFF8598AA),
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionText, this.onAction});

  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 16.5,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
      if (actionText != null && onAction != null)
        InkWell(
          onTap: onAction,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionText!,
                  style: const TextStyle(
                    color: Color(0xFF5A7591),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF5A7591),
                  size: 15,
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class _ToolsGrid extends StatelessWidget {
  const _ToolsGrid({
    required this.onBookmarks,
    required this.onLikes,
    required this.onHistory,
    required this.onAppeals,
  });

  final VoidCallback onBookmarks;
  final VoidCallback onLikes;
  final VoidCallback onHistory;
  final VoidCallback onAppeals;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppTheme.border),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F274969),
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        _ToolButton(
          icon: Icons.star_rounded,
          label: '我的收藏',
          iconColor: AppTheme.orange,
          bgColor: const Color(0xFFFFF0E8),
          onTap: onBookmarks,
        ),
        _ToolButton(
          icon: Icons.thumb_up_rounded,
          label: '我的点赞',
          iconColor: AppTheme.pink,
          bgColor: const Color(0xFFFFEEF3),
          onTap: onLikes,
        ),
        _ToolButton(
          icon: Icons.history_rounded,
          label: '浏览历史',
          iconColor: AppTheme.primary,
          bgColor: const Color(0xFFEAF4FF),
          onTap: onHistory,
        ),
        _ToolButton(
          icon: Icons.rate_review_outlined,
          label: '我的申诉',
          iconColor: AppTheme.mint,
          bgColor: const Color(0xFFE9F9F5),
          onTap: onAppeals,
        ),
      ],
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.bgColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: iconColor, size: 21),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF50677C), fontSize: 10.5),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecentPostsApi extends StatelessWidget {
  const _RecentPostsApi({
    required this.recentPostsFuture,
    required this.isGuest,
    required this.onOpenPostById,
    required this.onOpenPost,
    required this.onOpenHome,
    required this.onOpenComposer,
    required this.onRequireAuth,
  });

  final Future<ProfileListPage> recentPostsFuture;
  final bool isGuest;
  final OpenPostById? onOpenPostById;
  final ValueChanged<Post> onOpenPost;
  final VoidCallback onOpenHome;
  final VoidCallback? onOpenComposer;
  final VoidCallback? onRequireAuth;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileListPage>(
      future: recentPostsFuture,
      builder: (context, snapshot) {
        final items = snapshot.data?.items ?? const <ProfilePostItem>[];
        if (snapshot.connectionState == ConnectionState.waiting &&
            items.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (items.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F274969),
                  blurRadius: 16,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceBlue,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.article_outlined,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isGuest ? '暂时没有发布内容' : '还没有发布过帖子',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isGuest
                                ? '游客可以浏览和评论，注册邮箱账号后即可发布帖子。'
                                : '分享你的第一篇内容吧。',
                            style: const TextStyle(
                              color: Color(0xFF8DA0B2),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton(
                    onPressed: isGuest
                        ? (onRequireAuth ?? onOpenHome)
                        : (onOpenComposer ?? onOpenHome),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF376D9E),
                      backgroundColor: const Color(0xFFFAFDFF),
                      side: const BorderSide(color: Color(0xFFCFE0F2)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      isGuest ? '登录 / 注册' : '去发布',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F274969),
                blurRadius: 16,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  title: Text(
                    items[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '${items[i].communityName} · ${items[i].commentCount} 评论 · ${relativeTimeLabel(items[i].publishedAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8DA0B2),
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textSecondary,
                    size: 18,
                  ),
                  onTap: () {
                    if (onOpenPostById != null) {
                      onOpenPostById!(items[i].id);
                    } else {
                      onOpenPost(
                        Post(
                          id: items[i].id,
                          authorId: items[i].authorId,
                          communityId: items[i].communityId,
                          title: items[i].title,
                          content: items[i].contentPreview,
                          commentCount: items[i].commentCount,
                          likeCount: items[i].likeCount,
                          bookmarkCount: items[i].bookmarkCount,
                          createdAt: items[i].publishedAt,
                          updatedAt: items[i].publishedAt,
                          publishedAt: items[i].publishedAt,
                        ),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RecentPosts extends StatelessWidget {
  const _RecentPosts({
    required this.store,
    required this.currentUserId,
    this.isGuest = false,
    required this.onOpenPost,
    required this.onOpenHome,
    this.onOpenComposer,
    this.onRequireAuth,
  });

  final ForumStore store;
  final String? currentUserId;
  final bool isGuest;
  final ValueChanged<Post> onOpenPost;
  final VoidCallback onOpenHome;
  final VoidCallback? onOpenComposer;
  final VoidCallback? onRequireAuth;

  @override
  Widget build(BuildContext context) {
    final posts = currentUserId == null
        ? <Post>[]
        : store.posts.where((post) => post.authorId == currentUserId).toList();
    posts.sort((a, b) {
      final byTime = (b.publishedAt ?? b.createdAt).compareTo(
        a.publishedAt ?? a.createdAt,
      );
      return byTime == 0 ? b.id.compareTo(a.id) : byTime;
    });
    final recentPosts = posts.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F274969),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: recentPosts.isEmpty
          ? Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceBlue,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.article_outlined,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isGuest ? '暂时没有发布内容' : '还没有发布过帖子',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isGuest
                                ? '游客可以浏览和评论，注册邮箱账号后即可发布帖子。'
                                : '分享你的第一篇内容吧。',
                            style: const TextStyle(
                              color: Color(0xFF8DA0B2),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton(
                    onPressed: isGuest
                        ? (onRequireAuth ?? onOpenHome)
                        : (onOpenComposer ?? onOpenHome),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF376D9E),
                      backgroundColor: const Color(0xFFFAFDFF),
                      side: const BorderSide(color: Color(0xFFCFE0F2)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      isGuest ? '登录 / 注册' : '去发布',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: recentPosts
                  .map(
                    (post) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        post.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${post.section.label} · ${post.commentCount} 回复 · 发布于${relativeTimeLabel(post.publishedAt ?? post.createdAt)}',
                        style: const TextStyle(
                          color: Color(0xFF8DA0B2),
                          fontSize: 11,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppTheme.textSecondary,
                      ),
                      onTap: () => onOpenPost(post),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _ProfileTopbar extends StatelessWidget {
  const _ProfileTopbar({required this.onMessages, required this.onSettings});

  final VoidCallback onMessages;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Text(
          '我的',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 23,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
      ),
      IconButton(
        onPressed: onMessages,
        icon: const Icon(Icons.notifications_none_rounded, size: 22),
        tooltip: '通知',
      ),
      IconButton(
        onPressed: onSettings,
        icon: const Icon(Icons.settings_outlined, size: 22),
        tooltip: '设置',
      ),
    ],
  );
}

class _ExchangePreview extends StatelessWidget {
  const _ExchangePreview({
    required this.store,
    required this.onOpenStore,
    required this.onRedeem,
  });

  final ForumStore store;
  final VoidCallback onOpenStore;
  final ValueChanged<StoreProduct> onRedeem;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlue,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '兑换商店',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '用积分换论坛周边和实用好物',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.stars_rounded,
                    color: AppTheme.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${store.points}',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: storeProducts
                .take(2)
                .map(
                  (product) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _ProductMini(
                        product: product,
                        onTap: () => onRedeem(product),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onOpenStore,
              child: const Text('查看全部周边'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductMini extends StatelessWidget {
  const _ProductMini({required this.product, required this.onTap});

  final StoreProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(product.color),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(product.emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${product.points}积分',
                  style: const TextStyle(
                    color: AppTheme.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
