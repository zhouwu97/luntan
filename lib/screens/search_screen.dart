import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/interaction_controller.dart';
import '../data/api/platform_repository.dart';
import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';

enum SearchKind { all, posts, users, communities }

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.store,
    this.platform,
    required this.onOpenPost,
    required this.onOpenPostId,
    required this.interactionController,
    this.onOpenUserId,
    this.onOpenCommunityId,
  });

  final ForumStore store;
  final PlatformRepository? platform;
  final ValueChanged<Post> onOpenPost;
  final ValueChanged<String> onOpenPostId;
  final InteractionController interactionController;
  final ValueChanged<String>? onOpenUserId;
  final ValueChanged<String>? onOpenCommunityId;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final queryController = TextEditingController();
  final List<String> recentSearches = <String>[];
  SearchKind kind = SearchKind.all;
  Timer? debounce;
  SearchResult result = const SearchResult();
  String? nextCursor;
  bool hasMore = false;
  bool loading = false;
  bool loadingMore = false;
  Object? error;
  int generation = 0;
  String activeQuery = '';
  SearchKind activeKind = SearchKind.all;
  SharedPreferences? preferences;

  static const recentSearchesKey = 'search.recent.v1';
  static const suggestedSearches = <String>['黄油小姐', '润滑', '保养', '慢玩'];

  @override
  void dispose() {
    debounce?.cancel();
    queryController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
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
    if (value != null) queryController.text = value;
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
      });
    } catch (cause) {
      if (!mounted || requestGeneration != generation) return;
      setState(() {
        loadingMore = false;
        error = cause;
      });
    }
  }

  SearchResult _merge(SearchResult first, SearchResult second) {
    final posts = <String, SearchPost>{
      for (final item in first.posts) item.id: item,
    };
    final users = <String, SearchUser>{
      for (final item in first.users) item.id: item,
    };
    final communities = <String, SearchCommunity>{
      for (final item in first.communities) item.id: item,
    };
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
      posts: posts.values.toList(),
      users: users.values.toList(),
      communities: communities.values.toList(),
      nextCursor: second.nextCursor,
      hasMore: second.hasMore,
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

  @override
  Widget build(BuildContext context) {
    final query = queryController.text.trim();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: queryController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => search(),
          onSubmitted: (value) => search(value),
          decoration: const InputDecoration(
            hintText: '搜索帖子 / 用户 / 板块',
            prefixIcon: Icon(Icons.search_rounded),
            filled: true,
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              onPressed: () {
                queryController.clear();
                search();
              },
              icon: const Icon(Icons.clear_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          _KindTabs(
            selected: kind,
            onChanged: (newKind) {
              setState(() => kind = newKind);
              search();
            },
          ),
          Expanded(child: _body(query)),
        ],
      ),
    );
  }

  Widget _body(String query) {
    if (query.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppTheme.pagePadding),
        children: [
          if (recentSearches.isNotEmpty) ...[
            Row(
              children: [
                const Expanded(child: _GroupTitle(title: '最近搜索')),
                TextButton(
                  onPressed: _clearRecent,
                  child: const Text(
                    '清空',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
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
                    (item) => ActionChip(
                      label: Text(item),
                      onPressed: () => search(item),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 24),
          const _GroupTitle(title: '猜你想搜'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestedSearches
                .map(
                  (item) => ActionChip(
                    label: Text(item),
                    onPressed: () => search(item),
                  ),
                )
                .toList(),
          ),
          if (widget.platform == null) ...[
            const SizedBox(height: 24),
            const _GroupTitle(title: '推荐板块'),
            ...widget.store.communities.map(
              (community) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.surfaceBlue,
                  child: Icon(Icons.forum_outlined, color: AppTheme.primary),
                ),
                title: Text(community.name),
                subtitle: Text(community.description),
                onTap: widget.onOpenCommunityId == null
                    ? null
                    : () => widget.onOpenCommunityId!(community.id),
              ),
            ),
          ],
        ],
      );
    }
    if (widget.platform == null) return _mockBody(query);
    if (loading && result.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && result.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('搜索失败', style: TextStyle(color: AppTheme.textSecondary)),
            TextButton(onPressed: search, child: const Text('重试')),
          ],
        ),
      );
    }
    if (result.isEmpty) {
      return const Center(
        child: Text(
          '没有找到相关内容',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 240) _loadMore();
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.pagePadding),
        children: [
          if (result.posts.isNotEmpty) ...[
            const _GroupTitle(title: '帖子'),
            ...result.posts.map(
              (post) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  post.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${post.contentPreview}\n${post.communityName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => widget.onOpenPostId(post.id),
              ),
            ),
          ],
          if (result.users.isNotEmpty) ...[
            const _GroupTitle(title: '用户'),
            ...result.users.map(
              (user) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.surfaceBlue,
                  child: Icon(Icons.person, color: AppTheme.primary),
                ),
                title: Text(user.nickname),
                subtitle: Text('@${user.username}'),
                onTap: widget.onOpenUserId == null
                    ? null
                    : () => widget.onOpenUserId!(user.id),
              ),
            ),
          ],
          if (result.communities.isNotEmpty) ...[
            const _GroupTitle(title: '板块'),
            ...result.communities.map(
              (community) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.surfaceBlue,
                  child: Icon(Icons.forum_outlined, color: AppTheme.primary),
                ),
                title: Text(community.name),
                subtitle: Text(
                  '${community.description} · ${community.followerCount} 关注',
                ),
                onTap: widget.onOpenCommunityId == null
                    ? null
                    : () => widget.onOpenCommunityId!(community.id),
              ),
            ),
          ],
          if (loadingMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _mockBody(String query) {
    final posts = kind == SearchKind.users || kind == SearchKind.communities
        ? const <Post>[]
        : widget.store.search(query);
    final users = kind == SearchKind.posts || kind == SearchKind.communities
        ? const <User>[]
        : widget.store.searchUsers(query);
    final communities = kind == SearchKind.posts || kind == SearchKind.users
        ? const <Community>[]
        : widget.store.searchCommunities(query);
    if (posts.isEmpty && users.isEmpty && communities.isEmpty) {
      return const Center(
        child: Text(
          '没有找到相关内容',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppTheme.pagePadding),
      children: [
        if (posts.isNotEmpty) ...[
          const _GroupTitle(title: '帖子'),
          ...posts.map(
            (post) => ForumPostCard(
              post: post,
              onOpen: () => widget.onOpenPost(post),
              onOpenComments: () => widget.onOpenPost(post),
              onLike: () => widget.interactionController.togglePostLike(post),
              onBookmark: () =>
                  widget.interactionController.toggleBookmark(post),
              onMenu: null,
              interactionListenable: widget.interactionController,
            ),
          ),
        ],
        if (users.isNotEmpty) ...[
          const _GroupTitle(title: '用户'),
          ...users.map(
            (user) => ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.surfaceBlue,
                child: Icon(Icons.person, color: AppTheme.primary),
              ),
              title: Text(user.nickname),
              subtitle: Text('Lv.${user.level} · 活跃用户'),
            ),
          ),
        ],
        if (communities.isNotEmpty) ...[
          const _GroupTitle(title: '板块'),
          ...communities.map(
            (community) => ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.surfaceBlue,
                child: Icon(Icons.forum_outlined, color: AppTheme.primary),
              ),
              title: Text(community.name),
              subtitle: Text(community.description),
              onTap: widget.onOpenCommunityId == null
                  ? null
                  : () => widget.onOpenCommunityId!(community.id),
            ),
          ),
        ],
      ],
    );
  }
}

class _KindTabs extends StatelessWidget {
  const _KindTabs({required this.selected, required this.onChanged});
  final SearchKind selected;
  final ValueChanged<SearchKind> onChanged;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
    child: Row(
      children: SearchKind.values
          .map(
            (value) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(switch (value) {
                  SearchKind.all => '综合',
                  SearchKind.posts => '帖子',
                  SearchKind.users => '用户',
                  SearchKind.communities => '板块',
                }),
                selected: value == selected,
                onSelected: (_) => onChanged(value),
              ),
            ),
          )
          .toList(),
    ),
  );
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: AppTheme.textPrimary,
      ),
    ),
  );
}
