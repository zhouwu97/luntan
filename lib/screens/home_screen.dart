import 'package:flutter/material.dart';

import '../controllers/feed_controller.dart';
import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_post_card.dart';
import 'feature_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.feedController,
    required this.onOpenPost,
    required this.onOpenComments,
    required this.onOpenProfile,
    required this.onOpenComposer,
    required this.onOpenMessages,
    required this.onFeedback,
  });

  final ForumStore store;
  final FeedController feedController;
  final ValueChanged<Post> onOpenPost;
  final ValueChanged<Post> onOpenComments;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenComposer;
  final VoidCallback onOpenMessages;
  final ValueChanged<String> onFeedback;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ScrollController scrollController;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.feedController.initialLoad();
    });
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    await widget.feedController.refresh();
    if (mounted) widget.onFeedback('刷新完成，暂无新内容');
  }

  List<Post> get _visiblePosts {
    final posts = widget.feedController.state.items
        .where(
          (post) =>
              post.communityId == widget.store.selectedSection.communityId,
        )
        .where((post) {
          if (widget.store.selectedSort == FeedSort.featured) {
            return post.isFeatured;
          }
          return true;
        })
        .toList();
    if (widget.store.selectedSort == FeedSort.latest) {
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else if (widget.store.selectedSort == FeedSort.featured) {
      posts.sort((a, b) => b.commentCount.compareTo(a.commentCount));
    }
    return posts;
  }

  void openSearch() {
    showSearch<void>(
      context: context,
      delegate: _ForumSearchDelegate(
        store: widget.store,
        onOpenPost: widget.onOpenPost,
      ),
    );
  }

  void openFeature(String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FeaturePage(
          title: title,
          store: widget.store,
          onOpenPost: widget.onOpenPost,
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
        final isLoading =
            feedState.status == FeedStatus.initial ||
            feedState.status == FeedStatus.loading;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: refresh,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 360) {
                    widget.feedController.loadMore();
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
                        unread: widget.store.unreadMessages,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SectionTabs(store: widget.store),
                    ),
                    SliverToBoxAdapter(
                      child: _FeatureEntries(onTap: openFeature),
                    ),
                    SliverToBoxAdapter(
                      child: _FeedToolbar(
                        store: widget.store,
                        isRefreshing: feedState.isBusy,
                        onReply: () => openFeature('我的回复'),
                        onPublish: widget.onOpenComposer,
                        onRefresh: refresh,
                      ),
                    ),
                    if (isLoading || feedState.status == FeedStatus.loadingMore)
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
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
                      sliver:
                          feedState.status == FeedStatus.error &&
                              feedState.items.isEmpty
                          ? SliverToBoxAdapter(
                              child: _FeedError(
                                onRetry: widget.feedController.initialLoad,
                              ),
                            )
                          : isLoading
                          ? const SliverToBoxAdapter(
                              child: SizedBox(height: 180),
                            )
                          : posts.isEmpty
                          ? SliverToBoxAdapter(
                              child: _EmptyFeed(
                                sort: widget.store.selectedSort,
                              ),
                            )
                          : SliverList.builder(
                              itemCount: posts.length,
                              itemBuilder: (context, index) {
                                final post = posts[index];
                                return ForumPostCard(
                                  post: post,
                                  onOpen: () => widget.onOpenPost(post),
                                  onOpenComments: () => widget.onOpenComments(post),
                                  onLike: () => widget.store.toggleLike(post),
                                  onBookmark: () =>
                                      widget.store.toggleBookmark(post),
                                  onMenu: () => _showPostMenu(post),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
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
                color: post.isBookmarked ? AppTheme.orange : AppTheme.textSecondary,
              ),
              title: Text(post.isBookmarked ? '取消收藏' : '收藏帖子'),
              onTap: () {
                widget.store.toggleBookmark(post);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享帖子'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onFeedback('分享链接已复制');
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppTheme.orange),
              title: const Text('举报或屏蔽'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onFeedback('感谢反馈，我们会尽快处理');
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
                tooltip: '消息',
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
  const _SectionTabs({required this.store});

  final ForumStore store;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: ForumSection.values.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final section = ForumSection.values[index];
          final active = store.selectedSection == section;
          return GestureDetector(
            onTap: () => store.selectSection(section),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppTheme.textPrimary : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active ? AppTheme.textPrimary : AppTheme.border,
                ),
              ),
              child: Text(
                section.label,
                style: TextStyle(
                  color: active ? Colors.white : AppTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeatureEntries extends StatelessWidget {
  const _FeatureEntries({required this.onTap});

  final ValueChanged<String> onTap;

  static const entries = [
    ('榜', '排行榜', AppTheme.primary),
    ('热', '热门帖子', AppTheme.orange),
    ('搭', '穿搭分享', AppTheme.pink),
    ('活', '活动', AppTheme.mint),
    ('玩', '玩法分享', AppTheme.purple),
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
                      decoration: BoxDecoration(color: entry.$3.withValues(alpha: .12), shape: BoxShape.circle),
                      child: Center(child: Text(entry.$1, style: TextStyle(color: entry.$3, fontWeight: FontWeight.w900, fontSize: 15))),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(entry.$2, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600))),
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
    required this.store,
    required this.isRefreshing,
    required this.onReply,
    required this.onPublish,
    required this.onRefresh,
  });

  final ForumStore store;
  final bool isRefreshing;
  final VoidCallback onReply;
  final VoidCallback onPublish;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          ...FeedSort.values.map(
            (sort) => Padding(
              padding: const EdgeInsets.only(right: 18),
              child: GestureDetector(
                onTap: () => store.selectSort(sort),
                child: _SortItem(
                  label: sort.label,
                  active: store.selectedSort == sort,
                ),
              ),
            ),
          ),
          const Spacer(),
          _ToolbarButton(
            label: '回复',
            icon: Icons.chat_bubble_outline_rounded,
            onTap: onReply,
          ),
          const SizedBox(width: 4),
          _ToolbarButton(
            label: '发布',
            icon: Icons.edit_outlined,
            onTap: onPublish,
          ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: isRefreshing ? null : onRefresh,
            tooltip: '刷新',
            icon: AnimatedRotation(
              turns: isRefreshing ? .8 : 0,
              duration: const Duration(milliseconds: 450),
              child: const Icon(
                Icons.refresh_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
          ),
        ],
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
          duration: const Duration(milliseconds: 200),
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
            '${sort.label}暂无内容',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '换一个筛选条件看看吧',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

enum _SearchKind { all, posts, users, communities }

class _ForumSearchDelegate extends SearchDelegate<void> {
  _ForumSearchDelegate({required this.store, required this.onOpenPost});

  final ForumStore store;
  final ValueChanged<Post> onOpenPost;
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
    final posts = kind == _SearchKind.users || kind == _SearchKind.communities ? const <Post>[] : store.search(query);
    final users = kind == _SearchKind.posts || kind == _SearchKind.communities ? const <User>[] : store.searchUsers(query);
    final communities = kind == _SearchKind.posts || kind == _SearchKind.users ? const <Community>[] : store.searchCommunities(query);
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
          const Expanded(child: Center(child: Text('没有找到相关内容', style: TextStyle(color: AppTheme.textSecondary))))
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (posts.isNotEmpty) ...[
                  if (kind == _SearchKind.all) const _SearchSectionTitle(title: '帖子'),
                  ...posts.map((post) => ForumPostCard(post: post, onOpen: () { close(context, null); onOpenPost(post); }, onOpenComments: () { close(context, null); onOpenPost(post); }, onLike: () => store.toggleLike(post), onBookmark: () => store.toggleBookmark(post), onMenu: () {})),
                ],
                if (users.isNotEmpty) ...[
                  if (kind == _SearchKind.all) const _SearchSectionTitle(title: '用户'),
                  ...users.map((user) => ListTile(leading: CircleAvatar(backgroundColor: AppTheme.surfaceBlue, child: Text(user.nickname.characters.first)), title: Text(user.nickname), subtitle: Text('Lv.${user.level} · ${user.signature ?? '活跃用户'}'))),
                ],
                if (communities.isNotEmpty) ...[
                  if (kind == _SearchKind.all) const _SearchSectionTitle(title: '板块'),
                  ...communities.map((community) => ListTile(leading: const CircleAvatar(backgroundColor: AppTheme.surfaceBlue, child: Icon(Icons.forum_outlined, color: AppTheme.primary)), title: Text(community.name), subtitle: Text(community.description), onTap: () { store.selectSection(ForumSection.values.firstWhere((section) => section.communityId == community.id)); close(context, null); })),
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
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: Row(children: [_SearchKindButton(label: '综合', kind: _SearchKind.all, selected: selected, onChanged: onChanged), _SearchKindButton(label: '帖子', kind: _SearchKind.posts, selected: selected, onChanged: onChanged), _SearchKindButton(label: '用户', kind: _SearchKind.users, selected: selected, onChanged: onChanged), _SearchKindButton(label: '板块', kind: _SearchKind.communities, selected: selected, onChanged: onChanged)]));
}

class _SearchKindButton extends StatelessWidget {
  const _SearchKindButton({required this.label, required this.kind, required this.selected, required this.onChanged});

  final String label;
  final _SearchKind kind;
  final _SearchKind selected;
  final ValueChanged<_SearchKind> onChanged;

  @override
  Widget build(BuildContext context) => TextButton(onPressed: () => onChanged(kind), child: Text(label, style: TextStyle(color: selected == kind ? AppTheme.primary : AppTheme.textSecondary, fontWeight: selected == kind ? FontWeight.w800 : FontWeight.w500)));
}

class _SearchSectionTitle extends StatelessWidget {
  const _SearchSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)));
}
