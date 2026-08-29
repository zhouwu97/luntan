// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/feed_controller.dart';
import '../controllers/interaction_controller.dart';
import '../data/api/api_client.dart';
import '../data/api/platform_repository.dart';
import '../data/api/publish_repository.dart';
import '../data/api/ranking_repository.dart';
import '../data/api/store_repository.dart';
import '../data/app_links.dart';
import '../data/mock_forum_data.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';
import 'package:share_plus/share_plus.dart';
import 'feature_page.dart';
import 'search_screen.dart';

/// 首页导航是产品级固定结构，不依赖服务端返回顺序，也不把 QA/导入板块
/// 意外暴露给用户。
const homeCommunityIds = <String>[
  'community-unboxing',
  'community-campus',
  'community-daily',
];

List<Community> selectHomeCommunities(Iterable<Community> source) {
  final candidates = source
      .where((community) => community.status == CommunityStatus.active)
      .where(_isHomeCommunity)
      .toList();
  candidates.sort((a, b) {
    final byPriority = _homeCommunityPriority(
      a,
    ).compareTo(_homeCommunityPriority(b));
    if (byPriority != 0) return byPriority;
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    final byPosts = b.postCount.compareTo(a.postCount);
    return byPosts == 0 ? a.id.compareTo(b.id) : byPosts;
  });

  // 同一板块可能同时存在旧 ID 和导入 ID，优先保留排序靠前的那一个，
  // 避免用户看到两个同名 Tab 但点击后请求不同数据。
  final seenNames = <String>{};
  final seenIds = <String>{};
  return [
    for (final community in candidates)
      if (seenIds.add(community.id) && seenNames.add(community.name.trim()))
        community,
  ];
}

bool _isHomeCommunity(Community community) {
  if (community.id == 'community_qa' ||
      community.slug == 'qa' ||
      community.name.trim() == 'QA测试板块') {
    return false;
  }
  return homeCommunityIds.contains(community.id) ||
      community.id.startsWith('community-import-') ||
      const {'大型拆箱', '杂鱼日常', '酱紫社区'}.contains(community.name.trim());
}

int _homeCommunityPriority(Community community) {
  final knownIdIndex = homeCommunityIds.indexOf(community.id);
  if (knownIdIndex >= 0) return knownIdIndex;
  return switch (community.name.trim()) {
    '大型拆箱' => 0,
    '酱紫社区' => 1,
    '杂鱼日常' => 2,
    _ => 1000 + community.sortOrder,
  };
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
    this.canComment = true,
    this.canLike = true,
    this.canVote = true,
    this.canModerate = false,
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
    this.publishRepository,
    this.canManageRanking = false,
    this.onRefreshCompleted,
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
  final bool canComment;
  final bool canLike;
  final bool canVote;
  final bool canModerate;
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
  final PublishRepository? publishRepository;
  final bool canManageRanking;

  /// 首页内容刷新后通知应用层同步未读数。
  final Future<void> Function()? onRefreshCompleted;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _loadMoreThreshold = 600;
  static const int _maxViewportFillAttempts = 4;

  late final ScrollController scrollController;
  List<Community> communities = const [];
  String? selectedCommunityId;
  late FeedSort selectedSort;
  LatestOrder latestOrder = LatestOrder.post;
  final feedToolbarKey = GlobalKey();
  bool _autoFillingViewport = false;
  int _viewportFillAttempts = 0;
  bool _showBackToTop = false;
  bool _loadingCommunities = false;

  bool get isApiMode => widget.feedRepository != null;

  @override
  void initState() {
    super.initState();
    // 首页默认展示酱紫社区，作为中间主 Tab；发布默认板块也与首页保持一致。
    selectedCommunityId = 'community-campus';
    selectedSort = isApiMode ? FeedSort.latest : widget.store.selectedSort;
    latestOrder = isApiMode ? LatestOrder.post : LatestOrder.comment;
    communities = widget.communityRepository == null
        ? selectHomeCommunities(widget.store.communities)
        : const [];
    scrollController = ScrollController()..addListener(_onScroll);
    widget.feedController.addListener(_onFeedStateChanged);
    if (widget.communityRepository != null) {
      _loadCommunities();
    }
    // 有板块仓储时，先加载标签再请求默认的酱紫社区流，避免标签和列表状态短暂不同步。
    if (widget.communityRepository == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadFeed();
      });
    }
  }

  @override
  void dispose() {
    widget.feedController.removeListener(_onFeedStateChanged);
    scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    _resetViewportFillAttempts();
    await widget.feedController.refresh();
    if (!mounted) return;
    final hasRefreshError =
        widget.feedController.state.status == FeedStatus.error &&
        widget.feedController.state.items.isEmpty;
    widget.onFeedback(hasRefreshError ? '刷新失败，请重试' : '已经是最新内容');
    await widget.onRefreshCompleted?.call();
  }

  void _loadFeed() {
    // API 模式由首页自己的选择状态驱动查询；Mock 模式仍同步 ForumStore，
    // 这样两个 Adapter 都通过同一个 FeedController 进入查询接口。
    widget.feedController.setQuery(
      communityId: selectedCommunityId,
      sort: selectedSort.name,
      latestOrder: latestOrder,
    );
  }

  void _resetViewportFillAttempts() {
    _viewportFillAttempts = 0;
  }

  void _onFeedStateChanged() {
    final controllerCommunityId = widget.feedController.communityId;
    if (mounted &&
        controllerCommunityId != null &&
        controllerCommunityId != selectedCommunityId) {
      setState(() => selectedCommunityId = controllerCommunityId);
    }
    _scheduleViewportFill();
  }

  void _scheduleViewportFill() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fillViewportIfNeeded();
    });
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final showBackToTop = position.pixels > _loadMoreThreshold;
    if (showBackToTop != _showBackToTop) {
      setState(() => _showBackToTop = showBackToTop);
    }
    if (position.extentAfter <= _loadMoreThreshold) {
      _requestLoadMore();
    }
  }

  Future<void> _requestLoadMore() {
    return widget.feedController.loadMore();
  }

  Future<void> _fillViewportIfNeeded() async {
    if (_autoFillingViewport ||
        _viewportFillAttempts >= _maxViewportFillAttempts ||
        !mounted ||
        !scrollController.hasClients) {
      return;
    }

    final hasMore = widget.feedController.state.hasMore;
    final status = widget.feedController.state.status;
    final error = widget.feedController.state.error;
    if (!hasMore ||
        error != null ||
        status == FeedStatus.loading ||
        status == FeedStatus.loadingMore ||
        scrollController.position.maxScrollExtent > _loadMoreThreshold) {
      return;
    }

    _autoFillingViewport = true;
    _viewportFillAttempts += 1;
    try {
      await _requestLoadMore();
    } finally {
      _autoFillingViewport = false;
      _scheduleViewportFill();
    }
  }

  void _selectCommunity(String communityId) {
    _resetViewportFillAttempts();
    setState(() {
      selectedCommunityId = communityId;
    });
    if (!isApiMode) {
      widget.store.selectSection(_sectionForCommunity(communityId));
    }
    _loadFeed();
  }

  Future<void> _loadCommunities() async {
    if (mounted) setState(() => _loadingCommunities = true);
    try {
      final result = await widget.communityRepository!.getCommunities(
        status: CommunityStatus.active,
      );
      if (!mounted) return;
      final visibleCommunities = selectHomeCommunities(result);
      setState(() {
        communities = visibleCommunities;
        final preferred = visibleCommunities
            .where(
              (item) =>
                  item.id == 'community-campus' || item.name.trim() == '酱紫社区',
            )
            .toList();
        selectedCommunityId = preferred.isNotEmpty
            ? preferred.first.id
            : visibleCommunities.isEmpty
            ? 'community-campus'
            : visibleCommunities.first.id;
      });
      _resetViewportFillAttempts();
      _loadFeed();
    } catch (_) {
      if (!mounted) return;
      widget.onFeedback('板块加载失败，稍后可重试');
    } finally {
      if (mounted) setState(() => _loadingCommunities = false);
    }
  }

  ForumSection _sectionForCommunity(String communityId) =>
      switch (communityId) {
        'community-campus' => ForumSection.community,
        'community-daily' => ForumSection.daily,
        _ => ForumSection.unboxing,
      };

  void _selectSort(FeedSort sort) {
    _resetViewportFillAttempts();
    setState(() {
      selectedSort = sort;
    });
    if (!isApiMode) widget.store.selectSort(sort);
    _loadFeed();
  }

  void _selectLatestOrder(LatestOrder order) {
    _resetViewportFillAttempts();
    setState(() {
      latestOrder = order;
    });
    _loadFeed();
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
          duration: AppMotion.duration(context, AppMotion.normal),
          curve: AppMotion.standard,
        );
      } else if (scrollController.hasClients) {
        scrollController.animateTo(
          200,
          duration: AppMotion.duration(context, AppMotion.normal),
          curve: AppMotion.standard,
        );
      }
    });
  }

  Future<void> _handleFloatingAction() async {
    if (_showBackToTop && scrollController.hasClients) {
      await scrollController.animateTo(
        0,
        duration: AppMotion.duration(context, AppMotion.normal),
        curve: AppMotion.standard,
      );
      return;
    }
    await refresh();
  }

  List<Post> get _visiblePosts {
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
          if (selectedSort == FeedSort.recommended) {
            return post.isRecommended;
          }
          return true;
        })
        .toList();
    if (selectedSort == FeedSort.latest) {
      filtered.sort((a, b) {
        final DateTime timeA;
        final DateTime timeB;
        if (latestOrder == LatestOrder.comment) {
          timeA = a.activityAt ?? a.publishedAt ?? a.createdAt;
          timeB = b.activityAt ?? b.publishedAt ?? b.createdAt;
        } else {
          timeA = a.publishedAt ?? a.createdAt;
          timeB = b.publishedAt ?? b.createdAt;
        }
        final byTime = timeB.compareTo(timeA);
        return byTime == 0 ? b.id.compareTo(a.id) : byTime;
      });
    } else if (selectedSort == FeedSort.featured) {
      filtered.sort((a, b) => b.commentCount.compareTo(a.commentCount));
    } else if (selectedSort == FeedSort.hot) {
      filtered.sort((a, b) => b.commentCount.compareTo(a.commentCount));
    } else if (selectedSort == FeedSort.recommended) {
      filtered.sort((a, b) {
        final posA = a.recommendationPosition ?? 999999;
        final posB = b.recommendationPosition ?? 999999;
        final byPos = posA.compareTo(posB);
        return byPos != 0
            ? byPos
            : (b.publishedAt ?? b.createdAt).compareTo(
                a.publishedAt ?? a.createdAt,
              );
      });
    }
    return filtered;
  }

  void openSearch() {
    Navigator.of(context).push(
      AppMotion.pageRoute<void>(
        builder: (_) => SearchScreen(
          store: widget.store,
          platform: widget.platform,
          rankingRepository: widget.rankingRepository,
          communities: communities,
          communityRepository: widget.communityRepository,
          onOpenPost: widget.onOpenPost,
          onOpenPostId: widget.onOpenPostId,
          interactionController: widget.interactionController,
          onOpenUserId: widget.onOpenUserId,
          onOpenCommunityId: widget.onOpenCommunityId,
          isAuthenticated: widget.isAuthenticated,
          canComment: widget.canComment,
          canLike: widget.canLike,
          canVote: widget.canVote,
          onRequireAuth: widget.onRequireAuth,
        ),
      ),
    );
  }

  void openFeature(FeatureType type) {
    Navigator.of(context).push(
      AppMotion.pageRoute<void>(
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
          publishRepository: widget.publishRepository,
          canManageRanking: widget.canManageRanking,
          isAuthenticated: widget.isAuthenticated,
          canComment: widget.canComment,
          canLike: widget.canLike,
          canVote: widget.canVote,
          onRequireAuth: widget.onRequireAuth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, widget.feedController]),
      builder: (context, _) {
        final posts = _visiblePosts;
        final feedState = widget.feedController.state;
        final activeStatus = feedState.status;
        final activeHasMore = feedState.hasMore;
        final activeError = feedState.error;
        final showInitialSkeleton =
            activeStatus == FeedStatus.initial ||
            (activeStatus == FeedStatus.loading && posts.isEmpty);
        final showTopProgress = activeStatus == FeedStatus.loading;
        final loadMoreFailed =
            activeError != null &&
            posts.isNotEmpty &&
            activeStatus == FeedStatus.success;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: refresh,
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
                          unread: widget.unread ?? 0,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _SectionTabs(
                          communities: communities,
                          selectedCommunityId: selectedCommunityId,
                          onChanged: _selectCommunity,
                          loading: _loadingCommunities,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _FeatureEntries(onTap: openFeature),
                      ),
                      SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: feedToolbarKey,
                          child: _FeedToolbar(
                            selected: selectedSort,
                            selectedLatestOrder: latestOrder,
                            onSortChanged: _selectSort,
                            onLatestOrderChanged: _selectLatestOrder,
                          ),
                        ),
                      ),
                      if (showTopProgress)
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
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                        sliver:
                            activeStatus == FeedStatus.error && posts.isEmpty
                            ? SliverToBoxAdapter(
                                child: _FeedError(
                                  onRetry: widget.feedController.initialLoad,
                                ),
                              )
                            : showInitialSkeleton
                            ? const SliverToBoxAdapter(child: _FeedSkeleton())
                            : posts.isEmpty
                            ? SliverToBoxAdapter(
                                child: _EmptyFeed(sort: selectedSort),
                              )
                            : SliverList.builder(
                                itemCount: posts.length,
                                itemBuilder: (context, index) {
                                  final post = posts[index];
                                  final showActivity =
                                      selectedSort == FeedSort.latest &&
                                      latestOrder == LatestOrder.comment &&
                                      (post.lastCommentAt != null ||
                                          post.activityAt != null);
                                  return ForumPostCard(
                                    post: post,
                                    onOpen: () => widget.onOpenPost(post),
                                    onOpenComments: () =>
                                        widget.onOpenComments(post),
                                    onLike: () => widget.onToggleLike(post),
                                    onBookmark: () =>
                                        widget.onToggleBookmark(post),
                                    onMenu: () => _showPostMenu(post),
                                    contextMeta: showActivity
                                        ? '💬 最近回复 ${relativeTimeLabel(post.activityAt ?? post.lastCommentAt!)}'
                                        : null,
                                    interactionListenable:
                                        widget.interactionController,
                                  );
                                },
                              ),
                      ),
                      if (posts.isNotEmpty &&
                          !showInitialSkeleton &&
                          activeStatus != FeedStatus.loading)
                        SliverToBoxAdapter(
                          child: _FeedPaginationFooter(
                            status: activeStatus,
                            hasMore: activeHasMore,
                            loadMoreFailed: loadMoreFailed,
                            isCommunityFeed: selectedCommunityId != null,
                            onRetry: _requestLoadMore,
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _FloatingRefresh(
                    active: showTopProgress,
                    showBackToTop: _showBackToTop,
                    onTap: _handleFloatingAction,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
            if (widget.platform != null && widget.canModerate)
              ListTile(
                leading: Icon(
                  post.isRecommended
                      ? Icons.remove_circle_outline
                      : Icons.push_pin_outlined,
                  color: AppTheme.primary,
                ),
                title: Text(post.isRecommended ? '移出首页推荐' : '加入首页推荐'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    if (post.isRecommended) {
                      await widget.platform!.removeHomeRecommendation(post.id);
                    } else {
                      await widget.platform!.setHomeRecommendation(
                        postId: post.id,
                      );
                    }
                    if (!mounted) return;
                    widget.onFeedback(
                      post.isRecommended ? '已移出首页推荐' : '已加入首页推荐',
                    );
                    await widget.feedController.refresh();
                  } catch (error) {
                    if (mounted) {
                      widget.onFeedback(
                        userFacingApiMessage(error, fallback: '推荐操作失败，请稍后重试'),
                      );
                    }
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享帖子'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final shareUrl = AppLinks.post(post.id);
                try {
                  await Share.share(shareUrl, subject: '分享帖子');
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: shareUrl));
                  widget.onFeedback('系统分享不可用，帖子链接已复制');
                }
              },
            ),
            if (isApiMode && widget.platform != null)
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
                      '搜索帖子、用户、板块、榜单',
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
    this.loading = false,
  });

  final List<Community> communities;
  final String? selectedCommunityId;
  final ValueChanged<String> onChanged;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tabs = communities;
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
        child: tabs.isEmpty
            ? loading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Center(
                      child: Text(
                        '暂无可用板块',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    )
            : Row(
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
        duration: AppMotion.duration(context, AppMotion.normal),
        curve: AppMotion.emphasized,
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
    required this.selectedLatestOrder,
    required this.onSortChanged,
    required this.onLatestOrderChanged,
  });

  final FeedSort selected;
  final LatestOrder selectedLatestOrder;
  final ValueChanged<FeedSort> onSortChanged;
  final ValueChanged<LatestOrder> onLatestOrderChanged;

  @override
  Widget build(BuildContext context) {
    final showCapsule = selected == FeedSort.latest;
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
          if (showCapsule) ...[
            const SizedBox(width: 8),
            _LatestOrderCapsule(
              selectedOrder: selectedLatestOrder,
              onOrderChanged: onLatestOrderChanged,
            ),
          ],
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

class _LatestOrderCapsule extends StatelessWidget {
  const _LatestOrderCapsule({
    required this.selectedOrder,
    required this.onOrderChanged,
  });

  final LatestOrder selectedOrder;
  final ValueChanged<LatestOrder> onOrderChanged;

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
          _LatestOrderChip(
            label: '按回复',
            icon: Icons.chat_bubble_outline_rounded,
            active: selectedOrder == LatestOrder.comment,
            onTap: () => onOrderChanged(LatestOrder.comment),
          ),
          const SizedBox(
            height: 13,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: Color(0xFFE5EDF4),
            ),
          ),
          _LatestOrderChip(
            label: '按发帖',
            icon: Icons.article_outlined,
            active: selectedOrder == LatestOrder.post,
            onTap: () => onOrderChanged(LatestOrder.post),
          ),
        ],
      ),
    );
  }
}

class _LatestOrderChip extends StatelessWidget {
  const _LatestOrderChip({
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
      label: '$label排序',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.normal),
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          height: 22,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE7F3FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: foreground),
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
          duration: AppMotion.duration(context, AppMotion.normal),
          curve: AppMotion.standard,
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
  const _FloatingRefresh({
    required this.active,
    required this.showBackToTop,
    required this.onTap,
  });

  final bool active;
  final bool showBackToTop;
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
      label: widget.showBackToTop ? '返回顶部' : '刷新',
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
              child: Icon(
                widget.showBackToTop
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.refresh_rounded,
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

class _FeedPaginationFooter extends StatelessWidget {
  const _FeedPaginationFooter({
    required this.status,
    required this.hasMore,
    required this.loadMoreFailed,
    required this.isCommunityFeed,
    required this.onRetry,
  });

  final FeedStatus status;
  final bool hasMore;
  final bool loadMoreFailed;
  final bool isCommunityFeed;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (status == FeedStatus.loadingMore) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(0, 20, 0, 88),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
        ),
      );
    }
    if (loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 88),
        child: Center(
          child: TextButton(onPressed: onRetry, child: const Text('加载失败，点击重试')),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 88),
        child: Center(
          child: Text(
            isCommunityFeed ? '这个板块暂时只有这些内容' : '已经到底啦',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox(height: 88);
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
  const _EmptyFeed({required this.sort});

  final FeedSort sort;

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
            sort == FeedSort.recommended ? '暂无推荐内容' : '${sort.label}暂无内容',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sort == FeedSort.recommended ? '管理员推荐的精选帖子会出现在这里' : '换一个筛选条件看看吧',
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
  String? get searchFieldLabel => '搜索帖子、用户、板块、榜单';

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
