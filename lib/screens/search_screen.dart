import 'dart:async';

import 'package:flutter/material.dart';

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
  });

  final ForumStore store;
  final PlatformRepository? platform;
  final ValueChanged<Post> onOpenPost;
  final ValueChanged<String> onOpenPostId;
  final InteractionController interactionController;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final queryController = TextEditingController();
  final List<String> recentSearches = <String>[
    '新生攻略',
    '二手电脑',
    '食堂',
    '社团',
    '考研',
  ];
  SearchKind kind = SearchKind.all;
  Timer? debounce;
  Future<SearchResult>? future;

  @override
  void dispose() {
    debounce?.cancel();
    queryController.dispose();
    super.dispose();
  }

  void search([String? value]) {
    if (value != null) queryController.text = value;
    debounce?.cancel();
    final query = queryController.text.trim();
    if (value != null && query.isNotEmpty) _remember(query);
    if (query.isEmpty || widget.platform == null) {
      setState(() => future = null);
      return;
    }
    debounce = Timer(const Duration(milliseconds: 260), () {
      if (mounted) {
        setState(() => future = widget.platform!.search(query, type: kind.name));
      }
    });
  }

  void _remember(String query) {
    recentSearches
      ..remove(query)
      ..insert(0, query);
    if (recentSearches.length > 8) recentSearches.removeRange(8, recentSearches.length);
  }

  void _clearRecent() => setState(() => recentSearches.clear());

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
          onSubmitted: (_) => search(),
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
          Row(
            children: [
              const Expanded(
                child: _GroupTitle(title: '最近搜索'),
              ),
              if (recentSearches.isNotEmpty)
                TextButton(
                  onPressed: _clearRecent,
                  child: const Text(
                    '清空',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recentSearches
                .map((item) => ActionChip(label: Text(item), onPressed: () => search(item)))
                .toList(),
          ),
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
            ),
          ),
        ],
      );
    }
    if (widget.platform == null) return _mockBody(query);
    return FutureBuilder<SearchResult>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
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
        final result = snapshot.data ?? const SearchResult();
        if (result.isEmpty) {
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
                  subtitle:
                      Text('${community.description} · ${community.followerCount} 关注'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _mockBody(String query) {
    final posts = kind == SearchKind.users || kind == SearchKind.communities
        ? const <Post>[]
        : widget.store.search(query);
    final users = kind == SearchKind.posts || kind == SearchKind.communities
        ? const <User>[]
        : widget.store.searchUsers(query);
    final communities =
        kind == SearchKind.posts || kind == SearchKind.users
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
              onMenu: () {},
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