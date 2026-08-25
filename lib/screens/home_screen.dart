// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/feed_controller.dart';
import '../controllers/home_personal_feed_controller.dart';
import '../controllers/interaction_controller.dart';
import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../data/api/ranking_repository.dart';
import '../data/api/store_repository.dart';
import '../data/mock_forum_data.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';
import 'feature_page.dart';
import 'search_screen.dart';

/// 首页公开内容只展示正式社区，避免把验收用的 QA 板块作为默认入口。
List<Community> selectHomeCommunities(Iterable<Community> source) {
  final ids = <String>{};
  final names = <String>{};
  return source
      .where(
        (community) => community.id != 'community_qa' && community.slug != 'qa',
      )
      .where((community) {
        final name = community.name.trim();
        if (!ids.add(community.id) || (name.isNotEmpty && !names.add(name))) {
          return false;
        }
        return true;
      })
      .take(3)
      .toList();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.feedController,
    required this.onOpenPost,
    required this.onOpenComments,
    required this.onOpenProfile,
    required this.onOpenMessages,
    required this.onFeedback,
    required this.onToggleLike,
    required this.onToggleBookmark,
    required this.onRequireAuth,
    required this.onOpenPostId,
    required this.isAuthenticated,
    required this.personalFeedController,
    this.onOpenUserId,
    this.onOpenCommunityId,
    this.platform,
    this.unread,
    required this.interactionController,
    this.feedRepository,
    this.communityRepository,
    this.postRepository,
    this.rankingRepository,
    this.storeRepository,
  });

  final ForumStore store;
  final FeedController feedController;
  final ValueChanged<Post> onOpenPost;
  final ValueChanged<Post> onOpenComments;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenMessages;
  final ValueChanged<String> onFeedback;
  final ValueChanged<Post> onToggleLike;
  final ValueChanged<Post> onToggleBookmark;
  final VoidCallback onRequireAuth;
  final ValueChanged<String> onOpenPostId;
  final bool isAuthenticated;
  final HomePersonalFeedController personalFeedController;
  final ValueChanged<String>? onOpenUserId;
  final ValueChanged<String>? onOpenCommunityId;
  final PlatformRepository? platform;
  final int? unread;
  final InteractionController interactionController;
  final FeedRepository? feedRepository;
  final CommunityRepository? communityRepository;
  final PostRepository? postRepository;
  final RankingRepository? rankingRepository;
  final StoreRepository? storeRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ScrollController scrollController;
  List<Community> communities = const [];
  String? selectedCommunityId;
  late FeedSort selectedSort;
  HomeFeedMode feedMode = HomeFeedMode.public;
  HomeFeedMode? pendingPersonalMode;
  final feedToolbarKey = GlobalKey();

  bool get isApiMode => widget.feedRepository != null;
  bool get isPersonalMode => feedMode != HomeFeedMode.public;

  @override
  void initState() {
    super.initState();
    selectedCommunityId = widget.feedRepository == null
        ? widget.store.selectedSection.communityId
        : null;
    selectedSort = widget.store.selectedSort;
    communities = widget.feedRepository == null
        ? widget.store.communities
        : const [];
    scrollController = ScrollController();
    if (widget.communityRepository != null) {
      _loadCommunities();
    }
    // 有板块仓储时，首个 feed 查询要等板块选择完成，避免先发一次空条件请求。
    if (widget.communityRepository == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadFeed();
      });
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = pendingPersonalMode;
    if (!oldWidget.isAuthenticated &&
        widget.isAuthenticated &&
        pending != null) {
      pendingPersonalMode = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectPersonalMode(pending);
      });
    }
  }

  Future<void> refresh() async {
    if (isPersonalMode) {
      await widget.personalFeedController.refresh(mode: feedMode);
    } else {
      await widget.feedController.refresh();
    }
    if (!mounted) return;
    final hasRefreshError = isPersonalMode
        ? widget.personalFeedController.state.status == FeedStatus.error &&
              widget.personalFeedController.state.items.isEmpty
        : widget.feedController.state.status == FeedStatus.error &&
              widget.feedController.state.items.isEmpty;
    widget.onFeedback(hasRefreshError ? '刷新失败，请重试' : '已经是最新内容');
  }

  void _loadFeed() {
    // API 模式由首页自己的选择状态驱动查询；Mock 模式仍同步 ForumStore，
    // 这样两个 Adapter 都通过同一个 FeedController 进入查询接口。
    widget.feedController.setQuery(
      communityId: selectedCommunityId,
      sort: selectedSort.name,
    );
  }

  void _selectCommunity(String? communityId) {
    final wasPersonal = isPersonalMode;
    setState(() {
      selectedCommunityId = communityId;
      feedMode = HomeFeedMode.public;
      pendingPersonalMode = null;
    });
    if (wasPersonal) widget.personalFeedController.reset();
    if (!isApiMode && communityId != null) {
      widget.store.selectSection(_sectionForCommunity(communityId));
    }
    _loadFeed();
  }

  Future<void> _loadCommunities() async {
    try {
      final result = await widget.communityRepository!.getCommunities(
        status: CommunityStatus.active,
      );
      if (!mounted) return;
      final visibleCommunities = selectHomeCommunities(result);
      final nextSelectedCommunityId =
          visibleCommunities.any((item) => item.id == selectedCommunityId)
          ? selectedCommunityId
          : visibleCommunities.isEmpty
          ? null
          : visibleCommunities.first.id;
      final shouldReload = nextSelectedCommunityId != selectedCommunityId;
      setState(() {
        communities = visibleCommunities;
        selectedCommunityId = nextSelectedCommunityId;
      });
      if (shouldReload || visibleCommunities.isEmpty) _loadFeed();
    } catch (_) {
      if (!mounted) return;
      widget.onFeedback('板块加载失败，稍后可重试');
    }
  }

  ForumSection _sectionForCommunity(String communityId) =>
      switch (communityId) {
        'community-campus' => ForumSection.community,
        'community-daily' => ForumSection.daily,
        _ => ForumSection.unboxing,
      };

  void _selectSort(FeedSort sort) {
    final wasPersonal = isPersonalMode;
    setState(() {
      selectedSort = sort;
      feedMode = HomeFeedMode.public;
      pendingPersonalMode = null;
    });
    if (wasPersonal) widget.personalFeedController.reset();
    if (!isApiMode) widget.store.selectSort(sort);
    _loadFeed();
  }

  void _selectPersonalMode(HomeFeedMode mode) {
    if (mode == HomeFeedMode.public) return;
    if (isApiMode && !widget.isAuthenticated) {
      final alreadyWaitingForLogin = pendingPersonalMode != null;
      pendingPersonalMode = mode;
      if (!alreadyWaitingForLogin) widget.onRequireAuth();
      return;
    }
    setState(() {
      feedMode = mode;
      pendingPersonalMode = null;
    });
    widget.personalFeedController.selectMode(mode);
    _scrollToFeedStart();
  }

  void _scrollToFeedStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final toolbarContext = feedToolbarKey.currentContext;
      if (toolbarContext != null) {
        Scrollable.ensureVisible(
          toolbarContext,
          alignment: 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } else if (scrollController.hasClients) {
        scrollController.animateTo(
          200,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  List<Post> get _visiblePosts {
    if (isPersonalMode) return widget.personalFeedController.state.items;
    final posts = widget.feedController.state.items;
    // API 模式：板块与排序由服务端过滤，客户端只展示服务端结果，不再二次筛选/重排。
    if (widget.feedRepository != null) return posts;
    final filtered = posts
        .where(
          (post) =>
              selectedCommunityId == null ||
              post.communityId == selectedCommunityId,
        )
        .where((post) {
          if (selectedSort == FeedSort.featured) {
            return post.isFeatured;
          }
          return true;
        })
        .toList();
    if (selectedSort == FeedSort.latest) {
      filtered.sort((a, b) {
        final byTime = (b.publishedAt ?? b.createdAt).compareTo(
          a.publishedAt ?? a.createdAt,
        );
        return byTime == 0 ? b.id.compareTo(a.id) : byTime;
      });
    } else if (selectedSort == FeedSort.featured) {
      filtered.sort((a, b) => b.commentCount.compareTo(a.commentCount));
    }
    return filtered;
  }

  void openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchScreen(
          store: widget.store,
          platform: widget.platform,
          onOpenPost: widget.onOpenPost,
          onOpenPostId: widget.onOpenPostId,
          interactionController: widget.interactionController,
          onOpenUserId: widget.onOpenUserId,
          onOpenCommunityId: widget.onOpenCommunityId,
        ),
      ),
    );
  }

  void openFeature(FeatureType type) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FeaturePage(
          type: type,
          store: widget.store,
          onOpenPost: widget.onOpenPost,
          interactionController: widget.interactionController,
          onLike: widget.onToggleLike,
          onBookmark: widget.onToggleBookmark,
          feedRepository: widget.feedRepository,
          platformRepository: widget.platform,
          postRepository: widget.postRepository,
          rankingRepository: widget.rankingRepository,
          storeRepository: widget.storeRepository,
          isAuthenticated: widget.isAuthenticated,
          onRequireAuth: widget.onRequireAuth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.store,
        widget.feedController,
        widget.personalFeedController,
      ]),
      builder: (context, _) {
        final posts = _visiblePosts;
        final feedState = widget.feedController.state;
        final personalState = widget.personalFeedController.state;
        final activeStatus = isPersonalMode
            ? personalState.status
            : feedState.status;
        final activeIsBusy = isPersonalMode
            ? personalState.isBusy
            : feedState.isBusy;
        final showInitialSkeleton =
            activeStatus == FeedStatus.initial ||
            (activeStatus == FeedStatus.loading && posts.isEmpty);
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: refresh,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.extentAfter < 360) {
                        if (isPersonalMode) {
                          widget.personalFeedController.loadMore();
                        } else {
                          widget.feedController.loadMore();
                        }
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      controller: scrollController,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _Header(
                            onProfile: widget.onOpenProfile,
                            onSearch: openSearch,
                            onMessages: widget.onOpenMessages,
                            unread:
                                widget.unread ?? widget.store.unreadMessages,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _SectionTabs(
                            communities: communities,
                            selectedCommunityId: selectedCommunityId,
                            onChanged: _selectCommunity,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _FeatureEntries(onTap: openFeature),
                        ),
                        SliverToBoxAdapter(
                          child: KeyedSubtree(
                            key: feedToolbarKey,
                            child: _FeedToolbar(
                              selected: isPersonalMode ? null : selectedSort,
                              selectedMode: feedMode,
                              onSortChanged: _selectSort,
                              onModeChanged: _selectPersonalMode,
                            ),
                          ),
                        ),
                        if (isPersonalMode)
                          SliverToBoxAdapter(
                            child: _PersonalFeedHint(mode: feedMode),
                          ),
                        if (activeIsBusy)
                          const SliverToBoxAdapter(
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              color: AppTheme.primary,
                              backgroundColor: AppTheme.surfaceBlue,
                            ),
                          )
                        else
                          const SliverToBoxAdapter(child: SizedBox(height: 2)),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 88),
                          sliver:
                              activeStatus == FeedStatus.error && posts.isEmpty
                              ? SliverToBoxAdapter(
                                  child: _FeedError(
                                    onRetry: isPersonalMode
                                        ? () => widget.personalFeedController
                                              .refresh(mode: feedMode)
                                        : widget.feedController.initialLoad,
                                  ),
                                )
                              : showInitialSkeleton
                              ? const SliverToBoxAdapter(child: _FeedSkeleton())
                              : posts.isEmpty
                              ? SliverToBoxAdapter(
                                  child: _EmptyFeed(
                                    sort: selectedSort,
                                    mode: feedMode,
                                  ),
                                )
                              : SliverList.builder(
                                  itemCount: posts.length,
                                  itemBuilder: (context, index) {
                                    final post = posts[index];
                                    return ForumPostCard(
                                      post: post,
                                      onOpen: () => widget.onOpenPost(post),
                                      onOpenComments: () =>
                                          widget.onOpenComments(post),
                                      onLike: () => widget.onToggleLike(post),
                                      onBookmark: () =>
                                          widget.onToggleBookmark(post),
                                      onMenu: () => _showPostMenu(post),
                                      contextMeta:
                                          isPersonalMode &&
                                              feedMode ==
                                                  HomeFeedMode.receivedComments
                                          ? _personalContextMeta(post)
                                          : null,
                                      interactionListenable:
                                          widget.interactionController,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _FloatingRefresh(active: activeIsBusy, onTap: refresh),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _personalContextMeta(Post post) {
    final activityAt = widget.personalFeedController.activityAtFor(post.id);
    if (activityAt == null) return null;
    return '最近回复 ${relativeTimeLabel(activityAt)}';
  }

  void _showPostMenu(Post post) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                post.isBookmarked
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: post.isBookmarked
                    ? AppTheme.orange
                    : AppTheme.textSecondary,
              ),
              title: Text(post.isBookmarked ? '取消收藏' : '收藏帖子'),
              onTap: () {
                widget.onToggleBookmark(post);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享帖子'),
              onTap: () {
                Navigator.pop(sheetContext);
                final baseUrl = Uri.parse(
                  const String.fromEnvironment(
                    'WEB_BASE_URL',
                    defaultValue: 'https://luntan.app',
                  ),
                );
                final shareUrl = baseUrl
                    .resolve('/posts/${Uri.encodeComponent(post.id)}')
                    .toString();
                Clipboard.setData(ClipboardData(text: shareUrl));
                widget.onFeedback('帖子链接已复制');
              },
            ),
            if (widget.platform != null)
              ListTile(
                leading: const Icon(
                  Icons.flag_outlined,
                  color: AppTheme.orange,
                ),
                title: const Text('举报或屏蔽'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    await widget.platform!.report(
                      targetType: 'post',
                      targetId: post.id,
                      reasonCode: 'other',
                    );
                    widget.onFeedback('举报已提交，我们会尽快处理');
                  } catch (error) {
                    widget.onFeedback(
                      userFacingApiMessage(error, fallback: '举报失败，请稍后重试'),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onProfile,
    required this.onSearch,
    required this.onMessages,
    required this.unread,
  });

  final VoidCallback onProfile;
  final VoidCallback onSearch;
  final VoidCallback onMessages;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          InkResponse(
            onTap: onProfile,
            radius: 26,
            child: const CircleAvatar(
              radius: 21,
              backgroundColor: AppTheme.surfaceBlue,
              child: Text(
                '理',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onSearch,
              borderRadius: BorderRadius.circular(18),
              child: Ink(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '搜索帖子 / 用户 / 板块',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: onMessages,
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: AppTheme.textPrimary,
                  size: 25,
                ),
                tooltip: '系统通知',
              ),
              if (unread > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.pink,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.communities,
    required this.selectedCommunityId,
    required this.onChanged,
  });

  final List<Community> communities;
  final String? selectedCommunityId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = communities.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: Container(
        height: 46,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlue,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: tabs
              .map(
                (community) => Expanded(
                  child: _CommunityTab(
                    label: community.name,
                    active: selectedCommunityId == community.id,
                    onTap: () => onChanged(community.id),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _CommunityTab extends StatelessWidget {
  const _CommunityTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.tabMotion,
        curve: AppTheme.stateCurve,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _FeatureEntries extends StatelessWidget {
  const _FeatureEntries({required this.onTap});

  final ValueChanged<FeatureType> onTap;

  static const entries = [
    (
      Icons.emoji_events_outlined,
      FeatureType.ranking,
      Color(0xFFD9EBFF),
      Color(0xFF3F8FE8),
    ),
    (
      Icons.local_fire_department_outlined,
      FeatureType.hot,
      Color(0xFFFFE4D2),
      Color(0xFFF28B43),
    ),
    (
      Icons.checkroom_outlined,
      FeatureType.outfit,
      Color(0xFFF6DCE8),
      Color(0xFFDC7099),
    ),
    (
      Icons.calendar_month_outlined,
      FeatureType.activity,
      Color(0xFFD3F1EB),
      Color(0xFF2EAE98),
    ),
    (
      Icons.sports_esports_outlined,
      FeatureType.gameShare,
      Color(0xFFE2E0FF),
      Color(0xFF746CE5),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: Row(
          children: entries.map((entry) {
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(entry.$2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: entry.$3,
                        borderRadius: BorderRadius.circular(
                          AppTheme.iconContainerRadius,
                        ),
                      ),
                      child: Icon(entry.$1, color: entry.$4, size: 21),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        entry.$2.label,
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
          }).toList(),
        ),
      ),
    );
  }
}

class _FeedToolbar extends StatelessWidget {
  const _FeedToolbar({
    required this.selected,
    required this.selectedMode,
    required this.onSortChanged,
    required this.onModeChanged,
  });

  final FeedSort? selected;
  final HomeFeedMode selectedMode;
  final ValueChanged<FeedSort> onSortChanged;
  final ValueChanged<HomeFeedMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: FeedSort.values
                    .map(
                      (sort) => _SortItemButton(
                        sort: sort,
                        active: selected == sort,
                        onTap: () => onSortChanged(sort),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _FeedModeCapsule(
            selectedMode: selectedMode,
            onModeChanged: onModeChanged,
          ),
        ],
      ),
    );
  }
}

class _SortItemButton extends StatelessWidget {
  const _SortItemButton({
    required this.sort,
    required this.active,
    required this.onTap,
  });

  final FeedSort sort;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: GestureDetector(
      onTap: onTap,
      child: _SortItem(label: sort.label, active: active),
    ),
  );
}

class _FeedModeCapsule extends StatelessWidget {
  const _FeedModeCapsule({
    required this.selectedMode,
    required this.onModeChanged,
  });

  final HomeFeedMode selectedMode;
  final ValueChanged<HomeFeedMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD6E7F6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F456B8F),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FeedModeChip(
            label: '评论',
            icon: Icons.chat_bubble_outline_rounded,
            active: selectedMode == HomeFeedMode.receivedComments,
            onTap: () => onModeChanged(HomeFeedMode.receivedComments),
          ),
          const SizedBox(
            height: 13,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: Color(0xFFE5EDF4),
            ),
          ),
          _FeedModeChip(
            label: '帖子',
            icon: Icons.article_outlined,
            active: selectedMode == HomeFeedMode.myPosts,
            onTap: () => onModeChanged(HomeFeedMode.myPosts),
          ),
        ],
      ),
    );
  }
}

class _FeedModeChip extends StatelessWidget {
  const _FeedModeChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = active
        ? const Color(0xFF2388E7)
        : const Color(0xFF5E7E9B);
    return Semantics(
      button: true,
      selected: active,
      label: '$label模式',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          width: 56,
          height: 22,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE7F3FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 10.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonalFeedHint extends StatelessWidget {
  const _PersonalFeedHint({required this.mode});

  final HomeFeedMode mode;

  @override
  Widget build(BuildContext context) {
    final isComments = mode == HomeFeedMode.receivedComments;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlue,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          isComments ? '评论模式：按帖子最近收到其他用户评论的时间排序' : '帖子模式：仅显示我发布的帖子，按发布时间排序',
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 70),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: AppTheme.textSecondary,
            size: 42,
          ),
          const SizedBox(height: 12),
          const Text(
            '内容加载失败',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _SortItem extends StatelessWidget {
  const _SortItem({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: active ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontSize: 14,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        AnimatedContainer(
          duration: AppTheme.tabMotion,
          curve: AppTheme.contentCurve,
          width: active ? 20 : 0,
          height: 3,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: AppTheme.primary),
      label: Text(
        label,
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 3),
      ),
    );
  }
}

class _FloatingRefresh extends StatefulWidget {
  const _FloatingRefresh({required this.active, required this.onTap});

  final bool active;
  final Future<void> Function() onTap;

  @override
  State<_FloatingRefresh> createState() => _FloatingRefreshState();
}

class _FloatingRefreshState extends State<_FloatingRefresh>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.active) controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _FloatingRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !controller.isAnimating) {
      controller.repeat();
    } else if (!widget.active && controller.isAnimating) {
      controller.stop();
      controller.value = 0;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '刷新',
      child: Material(
        color: Colors.white,
        elevation: 5,
        shadowColor: const Color(0x2A284A6E),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: widget.active ? null : widget.onTap,
          borderRadius: BorderRadius.circular(15),
          child: Ink(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppTheme.border),
            ),
            child: RotationTransition(
              turns: controller,
              child: const Icon(
                Icons.refresh_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (index) => Container(
          height: index == 0 ? 250 : 176,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _SkeletonBlock(width: 34, height: 34, radius: 17),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _SkeletonBlock(width: 92, height: 10),
                        SizedBox(height: 7),
                        _SkeletonBlock(width: 132, height: 8),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SkeletonBlock(width: double.infinity, height: 14),
              const SizedBox(height: 9),
              const _SkeletonBlock(width: 210, height: 11),
              if (index == 0) ...[
                const SizedBox(height: 15),
                const Expanded(child: _SkeletonBlock(width: double.infinity)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    this.width = double.infinity,
    this.height = 12,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlue,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.sort, required this.mode});

  final FeedSort sort;
  final HomeFeedMode mode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 70),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(
            Icons.auto_awesome_mosaic_outlined,
            color: AppTheme.primary,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            switch (mode) {
              HomeFeedMode.receivedComments => '还没有收到评论',
              HomeFeedMode.myPosts => '还没有发布帖子',
              HomeFeedMode.public => '${sort.label}暂无内容',
            },
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            switch (mode) {
              HomeFeedMode.receivedComments => '有新回复的帖子会出现在这里',
              HomeFeedMode.myPosts => '发布一篇帖子，和社区开始交流吧',
              HomeFeedMode.public => '换一个筛选条件看看吧',
            },
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

enum _SearchKind { all, posts, users, communities }

class _ForumSearchDelegate extends SearchDelegate<void> {
  _ForumSearchDelegate({
    required this.store,
    required this.onOpenPost,
    required this.onOpenPostId,
  });

  final ForumStore store;
  final ValueChanged<Post> onOpenPost;
  final ValueChanged<String> onOpenPostId;
  _SearchKind kind = _SearchKind.all;

  @override
  String? get searchFieldLabel => '搜索帖子 / 用户 / 板块';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        onPressed: () => query = '',
        icon: const Icon(Icons.clear_rounded),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final posts = kind == _SearchKind.users || kind == _SearchKind.communities
        ? const <Post>[]
        : store.search(query);
    final users = kind == _SearchKind.posts || kind == _SearchKind.communities
        ? const <User>[]
        : store.searchUsers(query);
    final communities = kind == _SearchKind.posts || kind == _SearchKind.users
        ? const <Community>[]
        : store.searchCommunities(query);
    final empty = posts.isEmpty && users.isEmpty && communities.isEmpty;
    return Column(
      children: [
        _SearchKinds(
          selected: kind,
          onChanged: (value) {
            kind = value;
            showSuggestions(context);
          },
        ),
        if (empty)
          const Expanded(
            child: Center(
              child: Text(
                '没有找到相关内容',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (posts.isNotEmpty) ...[
                  if (kind == _SearchKind.all)
                    const _SearchSectionTitle(title: '帖子'),
                  ...posts.map(
                    (post) => ForumPostCard(
                      post: post,
                      onOpen: () {
                        close(context, null);
                        onOpenPost(post);
                      },
                      onOpenComments: () {
                        close(context, null);
                        onOpenPost(post);
                      },
                      onLike: () => store.toggleLike(post),
                      onBookmark: () => store.toggleBookmark(post),
                      onMenu: null,
                    ),
                  ),
                ],
                if (users.isNotEmpty) ...[
                  if (kind == _SearchKind.all)
                    const _SearchSectionTitle(title: '用户'),
                  ...users.map(
                    (user) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.surfaceBlue,
                        child: Text(user.nickname.characters.first),
                      ),
                      title: Text(user.nickname),
                      subtitle: Text(
                        'Lv.${user.level} · ${user.signature ?? '活跃用户'}',
                      ),
                    ),
                  ),
                ],
                if (communities.isNotEmpty) ...[
                  if (kind == _SearchKind.all)
                    const _SearchSectionTitle(title: '板块'),
                  ...communities.map(
                    (community) => ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppTheme.surfaceBlue,
                        child: Icon(
                          Icons.forum_outlined,
                          color: AppTheme.primary,
                        ),
                      ),
                      title: Text(community.name),
                      subtitle: Text(community.description),
                      onTap: () {
                        store.selectSection(
                          ForumSection.values.firstWhere(
                            (section) => section.communityId == community.id,
                          ),
                        );
                        close(context, null);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _SearchKinds extends StatelessWidget {
  const _SearchKinds({required this.selected, required this.onChanged});

  final _SearchKind selected;
  final ValueChanged<_SearchKind> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: Row(
      children: [
        _SearchKindButton(
          label: '综合',
          kind: _SearchKind.all,
          selected: selected,
          onChanged: onChanged,
        ),
        _SearchKindButton(
          label: '帖子',
          kind: _SearchKind.posts,
          selected: selected,
          onChanged: onChanged,
        ),
        _SearchKindButton(
          label: '用户',
          kind: _SearchKind.users,
          selected: selected,
          onChanged: onChanged,
        ),
        _SearchKindButton(
          label: '板块',
          kind: _SearchKind.communities,
          selected: selected,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _SearchKindButton extends StatelessWidget {
  const _SearchKindButton({
    required this.label,
    required this.kind,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final _SearchKind kind;
  final _SearchKind selected;
  final ValueChanged<_SearchKind> onChanged;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => onChanged(kind),
    child: Text(
      label,
      style: TextStyle(
        color: selected == kind ? AppTheme.primary : AppTheme.textSecondary,
        fontWeight: selected == kind ? FontWeight.w800 : FontWeight.w500,
      ),
    ),
  );
}

class _SearchSectionTitle extends StatelessWidget {
  const _SearchSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
