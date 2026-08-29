import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/interaction_controller.dart';
import '../data/api/platform_repository.dart' hide RankingItem;
import '../data/api/ranking_repository.dart';
import '../data/mock_forum_data.dart';
import '../data/repositories/mock_repositories.dart';
import '../domain/models.dart' show CommunityStatus;
import '../domain/repositories.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../widgets/search/search_community_row.dart';
import '../widgets/search/search_post_row.dart';
import '../widgets/search/search_section.dart';
import '../widgets/search/search_skeleton.dart';
import '../widgets/search/search_user_row.dart';
import 'ranking_page.dart';

enum SearchKind { all, posts, users, communities, toys }

extension SearchKindLabel on SearchKind {
  String get label => switch (this) {
    SearchKind.all => '综合',
    SearchKind.posts => '帖子',
    SearchKind.users => '用户',
    SearchKind.communities => '板块',
    SearchKind.toys => '榜单',
  };
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.store,
    this.platform,
    this.rankingRepository,
    this.communities = const [],
    this.communityRepository,
    required this.onOpenPost,
    required this.onOpenPostId,
    required this.interactionController,
    this.onOpenUserId,
    this.onOpenCommunityId,
    this.isAuthenticated = false,
    this.canComment = false,
    this.canLike = false,
    this.canVote = false,
    this.onRequireAuth,
  });

  final ForumStore store;
  final PlatformRepository? platform;
  final RankingRepository? rankingRepository;
  final List<Community> communities;
  final CommunityRepository? communityRepository;
  final ValueChanged<Post> onOpenPost;
  final ValueChanged<String> onOpenPostId;
  final InteractionController interactionController;
  final ValueChanged<String>? onOpenUserId;
  final ValueChanged<String>? onOpenCommunityId;
  final bool isAuthenticated;
  final bool canComment;
  final bool canLike;
  final bool canVote;
  final VoidCallback? onRequireAuth;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final queryController = TextEditingController();
  final searchFocusNode = FocusNode();
  final scrollController = ScrollController();
  final List<String> recentSearches = <String>[];
  SearchKind kind = SearchKind.all;
  Timer? debounce;
  SearchResult result = const SearchResult();
  String? nextCursor;
  bool hasMore = false;
  bool loading = false;
  bool loadingMore = false;
  Object? error;
  Object? loadMoreError;
  int generation = 0;
  String activeQuery = '';
  SearchKind activeKind = SearchKind.all;
  SharedPreferences? preferences;
  List<Community> recommendedCommunities = const [];

  static const recentSearchesKey = 'search.recent.v1';
  static const suggestedSearches = <String>['黄油小姐', '润滑', '保养', '慢玩', '樱川爱'];

  @override
  void dispose() {
    debounce?.cancel();
    queryController.dispose();
    searchFocusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    recommendedCommunities = widget.communities;
    _loadRecentSearches();
    if (widget.platform != null &&
        recommendedCommunities.isEmpty &&
        widget.communityRepository != null) {
      unawaited(_loadRecommendedCommunities());
    }
  }

  Future<void> _loadRecommendedCommunities() async {
    try {
      final loaded = await widget.communityRepository!.getCommunities(
        status: CommunityStatus.active,
      );
      if (!mounted) return;
      setState(() => recommendedCommunities = loaded);
    } catch (_) {
      // 推荐板块加载失败不影响搜索主流程，也不回退到 API 模式的本地种子数据。
    }
  }

  Future<void> _loadRecentSearches() async {
    final value = await SharedPreferences.getInstance();
    if (!mounted) return;
    preferences = value;
    final saved = value.getStringList(recentSearchesKey);
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        recentSearches
          ..clear()
          ..addAll(saved.take(8));
      });
    }
  }

  void search([String? value]) {
    if (value != null) {
      queryController.text = value;
      queryController.selection = TextSelection.fromPosition(
        TextPosition(offset: value.length),
      );
    }
    debounce?.cancel();
    final query = queryController.text.trim();
    if (value != null && query.isNotEmpty) _remember(query);
    if (query.isEmpty || widget.platform == null) {
      generation += 1;
      setState(() {
        result = const SearchResult();
        nextCursor = null;
        hasMore = false;
        loading = false;
        loadingMore = false;
        error = null;
        loadMoreError = null;
      });
      return;
    }
    debounce = Timer(const Duration(milliseconds: 260), () {
      if (mounted) _startSearch(query, kind);
    });
  }

  void _startSearch(String query, SearchKind searchKind) {
    final requestGeneration = ++generation;
    activeQuery = query;
    activeKind = searchKind;
    setState(() {
      result = const SearchResult();
      nextCursor = null;
      hasMore = false;
      loading = true;
      loadingMore = false;
      error = null;
      loadMoreError = null;
    });
    unawaited(_loadFirst(requestGeneration, query, searchKind));
  }

  Future<void> _loadFirst(
    int requestGeneration,
    String query,
    SearchKind searchKind,
  ) async {
    try {
      final page = await widget.platform!.search(query, type: searchKind.name);
      if (!mounted || requestGeneration != generation) return;
      setState(() {
        result = page;
        nextCursor = page.nextCursor;
        hasMore = page.hasMore;
        loading = false;
        loadMoreError = null;
      });
    } catch (cause) {
      if (!mounted || requestGeneration != generation) return;
      setState(() {
        loading = false;
        error = cause;
      });
    }
  }

  Future<void> _loadMore() async {
    if (widget.platform == null || loading || loadingMore || !hasMore) return;
    final cursor = nextCursor;
    if (cursor == null || activeQuery.isEmpty) return;
    final requestGeneration = generation;
    setState(() => loadingMore = true);
    try {
      final page = await widget.platform!.search(
        activeQuery,
        type: activeKind.name,
        cursor: cursor,
      );
      if (!mounted || requestGeneration != generation) return;
      setState(() {
        result = _merge(result, page);
        nextCursor = page.nextCursor;
        hasMore = page.hasMore && page.nextCursor != cursor;
        loadingMore = false;
        loadMoreError = null;
      });
    } catch (cause) {
      if (!mounted || requestGeneration != generation) return;
      setState(() {
        loadingMore = false;
        loadMoreError = cause;
      });
    }
  }

  SearchResult _merge(SearchResult first, SearchResult second) {
    final toys = <String, SearchToy>{
      for (final item in first.toys) item.id: item,
    };
    final posts = <String, SearchPost>{
      for (final item in first.posts) item.id: item,
    };
    final users = <String, SearchUser>{
      for (final item in first.users) item.id: item,
    };
    final communities = <String, SearchCommunity>{
      for (final item in first.communities) item.id: item,
    };
    for (final item in second.toys) {
      toys.putIfAbsent(item.id, () => item);
    }
    for (final item in second.posts) {
      posts.putIfAbsent(item.id, () => item);
    }
    for (final item in second.users) {
      users.putIfAbsent(item.id, () => item);
    }
    for (final item in second.communities) {
      communities.putIfAbsent(item.id, () => item);
    }
    return SearchResult(
      toys: toys.values.toList(),
      posts: posts.values.toList(),
      users: users.values.toList(),
      communities: communities.values.toList(),
      nextCursor: second.nextCursor,
      hasMore: second.hasMore,
    );
  }

  void _openToyDetail(SearchToy toy) {
    final scoreStr = toy.score == toy.score.roundToDouble()
        ? toy.score.toStringAsFixed(0)
        : toy.score.toStringAsFixed(1);
    final asset = toy.rank == 1
        ? 'assets/ranking/hero.webp'
        : 'assets/ranking/${toy.assetKey}';
    final item = RankingItem(
      id: toy.id,
      rank: toy.rank,
      name: toy.name,
      hot: rankingWantCountText(toy.wantCount),
      tags: toy.tags,
      ratings: '${toy.ratingCount}人评分',
      score: scoreStr,
      asset: asset,
      remoteImageUrl: toy.coverUrl,
      couponUrl: toy.couponUrl,
      sourceUrl: toy.sourceUrl,
      merchant: toy.merchant,
      releaseYear: toy.releaseYear,
      description: toy.description,
      category: toy.category,
      segments: toy.segments,
      ratingDistribution: toy.id == 'toy-butter-2'
          ? const {8: 5, 9: 12}
          : const {},
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RankingItemDetailPage(
          item: item,
          repository: widget.rankingRepository,
          isAuthenticated: widget.isAuthenticated,
          canComment: widget.canComment,
          canLike: widget.canLike,
          canVote: widget.canVote,
          onRequireAuth: widget.onRequireAuth,
        ),
      ),
    );
  }

  void _remember(String query) {
    recentSearches
      ..remove(query)
      ..insert(0, query);
    if (recentSearches.length > 8) {
      recentSearches.removeRange(8, recentSearches.length);
    }
    preferences?.setStringList(recentSearchesKey, recentSearches);
  }

  void _clearRecent() {
    setState(() => recentSearches.clear());
    preferences?.remove(recentSearchesKey);
  }

  void _switchKind(SearchKind newKind) {
    if (kind == newKind) return;
    setState(() => kind = newKind);
    final query = queryController.text.trim();
    if (query.isNotEmpty && widget.platform != null) {
      _startSearch(query, newKind);
    }
    if (scrollController.hasClients) {
      scrollController.animateTo(
        0,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = queryController.text.trim();
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部搜索输入区
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: AppTheme.textPrimary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                        border: Border.all(color: AppTheme.border),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: queryController,
                              focusNode: searchFocusNode,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                hintText: '搜索帖子、用户、板块、榜单',
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                filled: false,
                                isDense: true,
                              ),
                              onChanged: (_) => search(),
                              onSubmitted: (value) {
                                search(value);
                                searchFocusNode.unfocus();
                              },
                            ),
                          ),
                          if (queryController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                queryController.clear();
                                search();
                                searchFocusNode.requestFocus();
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.cancel_rounded,
                                  size: 18,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 分类选择轻量 Segment
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: _KindTabs(selected: kind, onChanged: _switchKind),
            ),

            // 主体内容
            Expanded(child: _buildBody(query)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(String query) {
    if (query.isEmpty) {
      return _buildSearchHome();
    }
    if (widget.platform == null) {
      return _buildMockBody(query);
    }
    if (loading && result.isEmpty) {
      return const SearchSkeleton(itemCount: 3);
    }
    if (error != null && result.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              '搜索失败，请检查网络后重试',
              style: TextStyle(
                fontSize: 13.5,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _startSearch(query, kind),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (result.isEmpty) {
      return _buildEmptyState(query);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 240) _loadMore();
        return false;
      },
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
        children: [
          // 搜索概要信息
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Text(
              '${kind.label} · 与 “$query” 相关的结果',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // 榜单商品模块优先展示，保证精确命中商品名时用户先看到榜单结果。
          if (result.toys.isNotEmpty &&
              (kind == SearchKind.all || kind == SearchKind.toys)) ...[
            SearchSectionHeader(
              title: '榜单商品',
              actionText: kind == SearchKind.all && result.toys.length >= 2
                  ? '查看全部 >'
                  : null,
              onAction: () => _switchKind(SearchKind.toys),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: result.toys
                    .map(
                      (toy) => _SearchToyCard(
                        toy: toy,
                        onTap: () => _openToyDetail(toy),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],

          // 帖子模块
          if (result.posts.isNotEmpty &&
              (kind == SearchKind.all || kind == SearchKind.posts)) ...[
            SearchSectionHeader(
              title: '帖子',
              actionText: kind == SearchKind.all && result.posts.length >= 2
                  ? '查看全部 >'
                  : null,
              onAction: () => _switchKind(SearchKind.posts),
            ),
            _buildGroupContainer(
              children: result.posts.map((post) {
                return SearchPostRow(
                  title: post.title,
                  snippet: post.contentPreview,
                  communityName: post.communityName,
                  authorName: post.authorName.isEmpty ? '用户' : post.authorName,
                  authorLevel: post.authorLevel,
                  timeLabel: relativeTimeLabel(post.createdAt),
                  commentCount: post.commentCount,
                  likeCount: post.likeCount,
                  viewCount: post.viewCount,
                  query: query,
                  onTap: () => widget.onOpenPostId(post.id),
                );
              }).toList(),
            ),
          ],

          // 用户模块
          if (result.users.isNotEmpty &&
              (kind == SearchKind.all || kind == SearchKind.users)) ...[
            SearchSectionHeader(
              title: '用户',
              actionText: kind == SearchKind.all && result.users.length >= 2
                  ? '查看全部 >'
                  : null,
              onAction: () => _switchKind(SearchKind.users),
            ),
            _buildGroupContainer(
              children: result.users.map((user) {
                return SearchUserRow(
                  nickname: user.nickname,
                  username: user.username,
                  level: 1,
                  query: query,
                  onTap: widget.onOpenUserId == null
                      ? () {}
                      : () => widget.onOpenUserId!(user.id),
                );
              }).toList(),
            ),
          ],

          // 板块模块
          if (result.communities.isNotEmpty &&
              (kind == SearchKind.all || kind == SearchKind.communities)) ...[
            SearchSectionHeader(
              title: '板块',
              actionText:
                  kind == SearchKind.all && result.communities.length >= 2
                  ? '查看全部 >'
                  : null,
              onAction: () => _switchKind(SearchKind.communities),
            ),
            _buildGroupContainer(
              children: result.communities.map((community) {
                return SearchCommunityRow(
                  name: community.name,
                  description:
                      '${community.description} · ${community.followerCount} 关注',
                  query: query,
                  onTap: widget.onOpenCommunityId == null
                      ? () {}
                      : () => widget.onOpenCommunityId!(community.id),
                );
              }).toList(),
            ),
          ],

          // 分页加载态与重试
          if (loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (loadMoreError != null)
            Center(
              child: TextButton(
                onPressed: _loadMore,
                child: const Text(
                  '加载更多失败，点击重试',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchHome() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      children: [
        // 最近搜索
        if (recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '最近搜索',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: _clearRecent,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '清空',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recentSearches
                .map(
                  (item) => InkWell(
                    onTap: () => search(item),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF51697E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 22),
        ],

        // 猜你想搜
        const Text(
          '猜你想搜',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestedSearches
              .map(
                (item) => InkWell(
                  onTap: () => search(item),
                  borderRadius: BorderRadius.circular(11),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF334A60),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),

        // 推荐板块（开放式列表）
        const SizedBox(height: 22),
        const Text(
          '推荐板块',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _buildGroupContainer(
          children:
              (widget.platform == null
                      ? (widget.communities.isEmpty
                            ? widget.store.communities
                            : widget.communities)
                      : recommendedCommunities)
                  .map((community) {
                    return SearchCommunityRow.fromCommunity(
                      community: community,
                      onTap: widget.onOpenCommunityId == null
                          ? () {}
                          : () => widget.onOpenCommunityId!(community.id),
                    );
                  })
                  .toList(),
        ),
      ],
    );
  }

  Widget _buildMockBody(String query) {
    final toys =
        (kind == SearchKind.posts ||
            kind == SearchKind.users ||
            kind == SearchKind.communities)
        ? const <SearchToy>[]
        : MockPlatformRepository.rankingToys
              .where(
                (toy) =>
                    '${toy.name} ${toy.merchant} ${toy.description} ${toy.tags.join(' ')}'
                        .toLowerCase()
                        .contains(query.trim().toLowerCase()),
              )
              .take(3)
              .toList();
    final posts =
        (kind == SearchKind.users ||
            kind == SearchKind.communities ||
            kind == SearchKind.toys)
        ? const <Post>[]
        : widget.store.search(query);
    final users =
        (kind == SearchKind.posts ||
            kind == SearchKind.communities ||
            kind == SearchKind.toys)
        ? const <User>[]
        : widget.store.searchUsers(query);
    final communities =
        (kind == SearchKind.posts ||
            kind == SearchKind.users ||
            kind == SearchKind.toys)
        ? const <Community>[]
        : widget.store.searchCommunities(query);

    if (toys.isEmpty && posts.isEmpty && users.isEmpty && communities.isEmpty) {
      return _buildEmptyState(query);
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
          child: Text(
            '${kind.label} · 与 “$query” 相关的结果',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (toys.isNotEmpty) ...[
          SearchSectionHeader(
            title: '榜单商品',
            actionText: kind == SearchKind.all && toys.length >= 2
                ? '查看全部 >'
                : null,
            onAction: () => _switchKind(SearchKind.toys),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: toys
                  .map(
                    (toy) => _SearchToyCard(
                      toy: toy,
                      onTap: () => _openToyDetail(toy),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        if (posts.isNotEmpty) ...[
          SearchSectionHeader(
            title: '帖子',
            actionText: kind == SearchKind.all && posts.length >= 3
                ? '查看全部 >'
                : null,
            onAction: () => _switchKind(SearchKind.posts),
          ),
          _buildGroupContainer(
            children: posts.map((post) {
              return SearchPostRow.fromPost(
                post: post,
                query: query,
                onTap: () => widget.onOpenPost(post),
              );
            }).toList(),
          ),
        ],
        if (users.isNotEmpty) ...[
          SearchSectionHeader(
            title: '用户',
            actionText: kind == SearchKind.all && users.length >= 3
                ? '查看全部 >'
                : null,
            onAction: () => _switchKind(SearchKind.users),
          ),
          _buildGroupContainer(
            children: users.map((user) {
              return SearchUserRow.fromUser(
                user: user,
                query: query,
                onTap: widget.onOpenUserId == null
                    ? () {}
                    : () => widget.onOpenUserId!(user.id),
              );
            }).toList(),
          ),
        ],
        if (communities.isNotEmpty) ...[
          SearchSectionHeader(
            title: '板块',
            actionText: kind == SearchKind.all && communities.length >= 3
                ? '查看全部 >'
                : null,
            onAction: () => _switchKind(SearchKind.communities),
          ),
          _buildGroupContainer(
            children: communities.map((community) {
              return SearchCommunityRow.fromCommunity(
                community: community,
                query: query,
                onTap: widget.onOpenCommunityId == null
                    ? () {}
                    : () => widget.onOpenCommunityId!(community.id),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildGroupContainer({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppTheme.border),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: children.length,
          separatorBuilder: (context, index) =>
              const Divider(height: 1, thickness: 1, color: Color(0xFFEDF2F6)),
          itemBuilder: (context, index) => children[index],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppTheme.surfaceBlue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 28,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '未找到与 “$query” 相关的内容',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '试试更换关键词或切换上方分类',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindTabs extends StatelessWidget {
  const _KindTabs({required this.selected, required this.onChanged});

  final SearchKind selected;
  final ValueChanged<SearchKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = [
      SearchKind.all,
      SearchKind.posts,
      SearchKind.users,
      SearchKind.communities,
      SearchKind.toys,
    ];

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: values.map((value) {
          final isSelected = value == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.standard,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? const [
                          BoxShadow(
                            color: Color(0x122D4B69),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  value.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF2E5F96)
                        : const Color(0xFF6C8093),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SearchToyCard extends StatelessWidget {
  const _SearchToyCard({required this.toy, required this.onTap});

  final SearchToy toy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final assetPath = toy.rank == 1
        ? 'assets/ranking/hero.webp'
        : 'assets/ranking/${toy.assetKey}';
    final scoreStr = toy.score == toy.score.roundToDouble()
        ? toy.score.toStringAsFixed(0)
        : toy.score.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: toy.coverUrl != null && toy.coverUrl!.isNotEmpty
                        ? Image.network(
                            toy.coverUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                Image.asset(
                                  assetPath,
                                  fit: BoxFit.contain,
                                  errorBuilder:
                                      (context, error, stackTrace) =>
                                          Container(
                                            color: const Color(0xFFF3F4F6),
                                            child: const Icon(
                                              Icons.toys_outlined,
                                              color: Color(0xFF9CA3AF),
                                            ),
                                          ),
                                ),
                          )
                        : Image.asset(
                            assetPath,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  color: const Color(0xFFF3F4F6),
                                  child: const Icon(
                                    Icons.toys_outlined,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#${toy.rank}',
                              style: const TextStyle(
                                color: Color(0xFFF7618E),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              toy.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF1F2937),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.favorite,
                            size: 13,
                            color: Color(0xFFF7618E),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            scoreStr,
                            style: const TextStyle(
                              color: Color(0xFFF7618E),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${toy.merchant} · ${toy.releaseYear} · ${toy.wantCount}人想冲',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11,
                        ),
                      ),
                      if (toy.tags.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 4,
                          children: toy.tags
                              .take(3)
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#$tag',
                                    style: const TextStyle(
                                      color: Color(0xFF4B5563),
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
