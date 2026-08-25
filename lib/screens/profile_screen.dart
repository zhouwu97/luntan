import 'package:flutter/material.dart';

import '../data/api/api_client.dart';
import '../data/api/auth_repository.dart';
import '../data/api/bookmark_repository.dart';
import '../data/api/profile_repository.dart';
import '../data/api/store_repository.dart';
import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import 'exchange_store_screen.dart';
import 'bookmark_folders_screen.dart';
import 'points_screen.dart';

typedef OpenPostById = void Function(String postId, {String? focusCommentId});

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
    this.storeRepository,
    this.bookmarkRepository,
    this.onOpenPostId,
    this.onOpenPostById,
    this.onLogout,
    this.onDeleteAccount,
    this.onRequireAuth,
    this.onOpenModeration,
    this.onOpenAppeals,
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
  final StoreRepository? storeRepository;
  final BookmarkRepository? bookmarkRepository;
  final ValueChanged<String>? onOpenPostId;
  final OpenPostById? onOpenPostById;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onDeleteAccount;
  final VoidCallback? onRequireAuth;
  final VoidCallback? onOpenModeration;
  final VoidCallback? onOpenAppeals;
  final void Function(String userId, bool followers)? onOpenRelations;
  final int refreshToken;

  @override
  Widget build(BuildContext context) {
    if (isApiMode && currentUser == null) {
      return _GuestProfileScreen(onRequireAuth: onRequireAuth);
    }
    if (isApiMode && profileRepository != null) {
      return _ApiProfileScreen(
        repository: profileRepository!,
        onOpenPost: onOpenPost,
        onOpenMessages: onOpenMessages,
        onFeedback: onFeedback,
        onLogout: onLogout,
        onDeleteAccount: onDeleteAccount,
        storeRepository: storeRepository,
        bookmarkRepository: bookmarkRepository,
        onOpenPostId: onOpenPostId,
        onOpenPostById: onOpenPostById,
        onOpenModeration: onOpenModeration,
        onOpenAppeals: onOpenAppeals,
        onOpenRelations: onOpenRelations,
        refreshToken: refreshToken,
      );
    }
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              _ProfileTopbar(
                onMessages: onOpenMessages,
                onSettings: () => _showSettings(context),
              ),
              const SizedBox(height: 16),
              _ProfileHero(user: currentUser, isApiMode: isApiMode),
              const SizedBox(height: 16),
              _StatsStrip(
                store: store,
                isApiMode: isApiMode,
                onTap: (label) => _showList(context, label),
              ),
              const SizedBox(height: 14),
              _PointsBalanceCard(
                balance: store.points,
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
              const SizedBox(height: 22),
              const Text(
                '常用功能',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _ProfileTool(
                    icon: Icons.star_rounded,
                    label: '我的收藏',
                    color: AppTheme.orange,
                    onTap: () => _openBookmarks(context),
                  ),
                  _ProfileTool(
                    icon: Icons.thumb_up_rounded,
                    label: '我的点赞',
                    color: AppTheme.pink,
                    onTap: () => _showList(context, '我的点赞'),
                  ),
                  _ProfileTool(
                    icon: Icons.history_rounded,
                    label: '浏览历史',
                    color: AppTheme.primary,
                    onTap: () => _showHistory(context),
                  ),
                  _ProfileTool(
                    icon: Icons.rate_review_outlined,
                    label: '我的申诉',
                    color: AppTheme.mint,
                    onTap: onOpenAppeals ?? () => onFeedback('当前模式暂不支持申诉'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (!isApiMode) ...[
                _ExchangePreview(
                  store: store,
                  onOpenStore: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ExchangeStoreScreen(store: store),
                    ),
                  ),
                  onRedeem: (product) => _redeem(context, product),
                ),
                const SizedBox(height: 18),
              ],
              const Text(
                '最近发布',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              _RecentPosts(
                store: store,
                currentUserId: currentUserId,
                onOpenPost: onOpenPost,
              ),
              const SizedBox(height: 24),
              Text(
                '杯友酱 · 把真实的玩具体验留在这里',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: .7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              leading: Icon(Icons.palette_outlined),
              title: Text('杯友主题'),
              trailing: Icon(Icons.check_rounded, color: AppTheme.primary),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('隐私与安全'),
              onTap: () {
                Navigator.pop(context);
                onFeedback('隐私设置已打开');
              },
            ),
            if (onLogout != null)
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppTheme.pink),
                title: const Text('退出登录'),
                onTap: () async {
                  Navigator.pop(context);
                  await onLogout!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于杯友酱'),
              onTap: () {
                Navigator.pop(context);
                onFeedback('当前版本 v1.0.0');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showList(BuildContext context, String label) {
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
                          label == '我的发布' ||
                                  label == '我的发帖' ||
                                  label == '我的评论' ||
                                  label == '我的回帖' ||
                                  label == '关注的吧'
                              ? '$label暂未接入'
                              : '$label暂时为空，去首页逛逛吧',
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

class _GuestProfileScreen extends StatelessWidget {
  const _GuestProfileScreen({this.onRequireAuth});

  final VoidCallback? onRequireAuth;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 34,
                backgroundColor: AppTheme.surfaceBlue,
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 36,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '登录后查看我的内容',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '收藏、历史、评论和积分都将在这里汇总',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onRequireAuth,
                child: const Text('登录 / 注册'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 正式模式的个人中心只依赖服务器返回的聚合数据和列表，不读取 ForumStore。
class _ApiProfileScreen extends StatefulWidget {
  const _ApiProfileScreen({
    required this.repository,
    required this.onOpenPost,
    required this.onOpenMessages,
    required this.onFeedback,
    this.storeRepository,
    this.bookmarkRepository,
    this.onOpenPostId,
    this.onOpenPostById,
    this.onLogout,
    this.onDeleteAccount,
    this.onOpenModeration,
    this.onOpenAppeals,
    this.onOpenRelations,
    required this.refreshToken,
  });

  final ProfileRepository repository;
  final ValueChanged<Post> onOpenPost;
  final VoidCallback onOpenMessages;
  final ValueChanged<String> onFeedback;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onDeleteAccount;
  final VoidCallback? onOpenModeration;
  final VoidCallback? onOpenAppeals;
  final void Function(String userId, bool followers)? onOpenRelations;
  final int refreshToken;
  final StoreRepository? storeRepository;
  final BookmarkRepository? bookmarkRepository;
  final ValueChanged<String>? onOpenPostId;
  final OpenPostById? onOpenPostById;

  @override
  State<_ApiProfileScreen> createState() => _ApiProfileScreenState();
}

class _ApiProfileScreenState extends State<_ApiProfileScreen> {
  late Future<ProfileSummary> profileFuture;
  late Future<PointsOverview>? pointsFuture;

  @override
  void initState() {
    super.initState();
    profileFuture = widget.repository.getProfile();
    pointsFuture = widget.storeRepository?.overview();
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
    setState(() {
      profileFuture = profile;
      pointsFuture = points;
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
            const SizedBox(height: 16),
            Row(
              children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: AppTheme.surfaceBlue,
                  child: Icon(
                    Icons.person_rounded,
                    color: AppTheme.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.nickname,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${profile.username} · Lv.${profile.level} · 信任${profile.trustLevel}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (profile.signature.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          profile.signature,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (widget.storeRepository != null) ...[
              const SizedBox(height: 14),
              FutureBuilder<PointsOverview>(
                future: pointsFuture,
                builder: (context, snapshot) => _PointsBalanceCard(
                  balance: snapshot.data?.balance,
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  _ApiStat(
                    value: profile.postCount,
                    label: '我的发布',
                    onTap: () => _showList('我的发布'),
                  ),
                  _ApiStat(
                    value: profile.commentCount,
                    label: '我的评论',
                    onTap: () => _showList('我的评论'),
                  ),
                  _ApiStat(
                    value: profile.followerCount,
                    label: '粉丝',
                    onTap: widget.onOpenRelations == null
                        ? null
                        : () => widget.onOpenRelations!(profile.id, true),
                  ),
                  _ApiStat(
                    value: profile.followingCount,
                    label: '关注',
                    onTap: widget.onOpenRelations == null
                        ? null
                        : () => widget.onOpenRelations!(profile.id, false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '常用功能',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _ProfileTool(
                  icon: Icons.star_rounded,
                  label: '我的收藏',
                  color: AppTheme.orange,
                  onTap: () => _openBookmarks(),
                ),
                _ProfileTool(
                  icon: Icons.thumb_up_rounded,
                  label: '我的点赞',
                  color: AppTheme.pink,
                  onTap: () => _showList('我的点赞'),
                ),
                _ProfileTool(
                  icon: Icons.history_rounded,
                  label: '浏览历史',
                  color: AppTheme.primary,
                  onTap: () => _showList('浏览历史'),
                ),
                _ProfileTool(
                  icon: Icons.rate_review_outlined,
                  label: '我的申诉',
                  color: AppTheme.mint,
                  onTap:
                      widget.onOpenAppeals ??
                      () => widget.onFeedback('当前模式暂不支持申诉'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              '最近发布',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _showList('我的发布'),
              icon: const Icon(Icons.article_outlined),
              label: const Text('查看我的全部帖子'),
            ),
            const SizedBox(height: 24),
            Text(
              '杯友酱 · 把真实的玩具体验留在这里',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: .7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );

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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              leading: Icon(Icons.palette_outlined),
              title: Text('杯友主题'),
              trailing: Icon(Icons.check_rounded, color: AppTheme.primary),
            ),
            if (widget.onLogout != null)
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppTheme.pink),
                title: const Text('退出登录'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await widget.onLogout!();
                },
              ),
            if (widget.onDeleteAccount != null)
              ListTile(
                leading: const Icon(
                  Icons.person_off_outlined,
                  color: AppTheme.pink,
                ),
                title: const Text('注销账号'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final confirmed =
                      await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('确认注销账号？'),
                          content: const Text(
                            '账号、认证信息、互动和通知将被清理，且无法恢复。请确认你已备份需要保留的内容。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('继续注销'),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                  if (!confirmed || !mounted) return;
                  try {
                    await widget.onDeleteAccount!();
                  } catch (error) {
                    if (mounted) {
                      widget.onFeedback(
                        userFacingApiMessage(error, fallback: '注销失败，请稍后重试'),
                      );
                    }
                  }
                },
              ),
            if (widget.onOpenModeration != null)
              ListTile(
                leading: const Icon(
                  Icons.gavel_outlined,
                  color: AppTheme.primary,
                ),
                title: const Text('审核中心'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onOpenModeration!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于杯友酱'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onFeedback('当前版本 v1.0.0');
              },
            ),
          ],
        ),
      ),
    );
  }
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
      });
    } catch (_) {
      // 允许滚动到底部后再次触发。
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  Future<void> _clearHistory() async {
    await widget.repository.clearHistory();
    if (mounted) _load();
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
              : const SizedBox(height: 6);
        }
        final item = items[index];
        final post = item;
        final isCommentList = widget.kind == 'comments';
        final activityAt = post.activityAt ?? post.publishedAt;
        final title = post.title;
        final subtitle = isCommentList
            ? '${post.communityName} · ${post.commentCount} 回复 · '
                  '最近回复于${relativeTimeLabel(activityAt)}'
            : '${post.communityName} · ${post.commentCount} 回复 · '
                  '发布于${relativeTimeLabel(post.publishedAt)}';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isCommentList
                ? Icons.mode_comment_outlined
                : (_isHistory ? Icons.history_rounded : Icons.article_outlined),
            color: isCommentList ? AppTheme.mint : AppTheme.primary,
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
    authorId: '',
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

class _ApiStat extends StatelessWidget {
  const _ApiStat({
    required this.value,
    required this.label,
    required this.onTap,
  });
  final int value;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _RecentPosts extends StatelessWidget {
  const _RecentPosts({
    required this.store,
    required this.currentUserId,
    required this.onOpenPost,
  });

  final ForumStore store;
  final String? currentUserId;
  final ValueChanged<Post> onOpenPost;

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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: recentPosts.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '还没有发布内容',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : Column(
              children: recentPosts
                  .map(
                    (post) => ListTile(
                      title: Text(
                        post.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${post.community?.name ?? post.section.label} · ${post.comments} 回复 · ${post.views} 浏览',
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
          ),
        ),
      ),
      IconButton(
        onPressed: onMessages,
        icon: const Icon(Icons.notifications_none_rounded, size: 22),
      ),
      IconButton(
        onPressed: onSettings,
        icon: const Icon(Icons.settings_outlined, size: 22),
      ),
    ],
  );
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({this.user, required this.isApiMode});

  final AuthUser? user;
  final bool isApiMode;

  @override
  Widget build(BuildContext context) {
    final nickname = user?.nickname.isNotEmpty == true
        ? user!.nickname
        : '小理不理';
    final level = user?.level ?? 8;
    return Row(
      children: [
        const CircleAvatar(
          radius: 32,
          backgroundColor: AppTheme.surfaceBlue,
          child: Text(
            '理',
            style: TextStyle(
              color: AppTheme.primary,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      nickname,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isApiMode ? '@${user?.username ?? '未登录'}' : '关注 15 · 粉丝 59',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '等级 Lv.$level · 活跃用户',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.store,
    required this.onTap,
    required this.isApiMode,
  });

  final ForumStore store;
  final ValueChanged<String> onTap;
  final bool isApiMode;

  @override
  Widget build(BuildContext context) {
    final stats = isApiMode
        ? [('—', '我的发布'), ('—', '我的评论'), ('—', '关注的吧')]
        : [
            (store.publishedCount.toString(), '我的发布'),
            (store.replyCount.toString(), '我的评论'),
            (store.followedBoards.toString(), '关注的吧'),
          ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          for (var index = 0; index < stats.length; index++) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(stats[index].$2),
                child: Column(
                  children: [
                    Text(
                      stats[index].$1,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stats[index].$2,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (index < stats.length - 1)
              const SizedBox(
                height: 36,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppTheme.border,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileTool extends StatelessWidget {
  const _ProfileTool({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(AppTheme.iconContainerRadius),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PointsBalanceCard extends StatelessWidget {
  const _PointsBalanceCard({
    required this.balance,
    required this.onOpenPoints,
    required this.onOpenStore,
  });

  final int? balance;
  final VoidCallback onOpenPoints;
  final VoidCallback onOpenStore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlue,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on_rounded, color: AppTheme.orange),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onOpenPoints,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '社区积分余额',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    balance == null ? '加载中…' : '${balance!} 积分',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton(onPressed: onOpenPoints, child: const Text('明细')),
          TextButton(onPressed: onOpenStore, child: const Text('兑换')),
        ],
      ),
    );
  }
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
